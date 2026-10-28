"""Checagens estruturais do GitOps para GKE, sobre os manifests já
renderizados pelo kustomize e os arquivos do repositório. Chamado por
scripts/ci/gitops-check.sh, que faz o render antes.

uso: python3 -P scripts/ci/checar_gitops.py <raiz do repositório> <pasta com os YAML renderizados>
requer: PyYAML
"""
import sys
from pathlib import Path

import yaml

RAIZ, RENDER = Path(sys.argv[1]), Path(sys.argv[2])
G = RAIZ / "deploy/gitops"
falhas = []


def ok(cond, msg):
    if not cond:
        falhas.append(msg)


def docs(path):
    return [d for d in yaml.safe_load_all(path.read_text(encoding="utf-8")) if isinstance(d, dict)]


apps = {"donation": "donation-service", "ngo": "ngo-service", "volunteer": "volunteer-service", "notification": "notification-service"}
roteados = {"donation", "ngo", "volunteer"}

for app, svc in apps.items():
    objs = docs(RENDER / f"app-{app}.yaml")
    kinds = {}
    for o in objs:
        kinds.setdefault(o["kind"], []).append(o)
    dep = kinds["Deployment"][0]
    pod = dep["spec"]["template"]["spec"]
    c = pod["containers"][0]
    env = {e["name"]: e for e in c.get("env", [])}
    ok(pod.get("serviceAccountName") == svc, f"{app}: serviceAccountName")
    ok(any(sa["metadata"]["name"] == svc for sa in kinds.get("ServiceAccount", [])), f"{app}: KSA ausente")
    ok(pod.get("terminationGracePeriodSeconds") == 60, f"{app}: terminationGracePeriodSeconds")
    psc, csc = pod.get("securityContext", {}), c.get("securityContext", {})
    ok(psc.get("runAsNonRoot") is True and psc.get("seccompProfile", {}).get("type") == "RuntimeDefault", f"{app}: securityContext do pod")
    ok(csc.get("allowPrivilegeEscalation") is False and csc.get("capabilities", {}).get("drop") == ["ALL"], f"{app}: securityContext do container")
    ok(c.get("lifecycle", {}).get("preStop") is not None, f"{app}: preStop")
    ok(pod.get("topologySpreadConstraints"), f"{app}: topologySpreadConstraints")
    ok(any(p["spec"]["selector"]["matchLabels"]["app"] == svc for p in kinds.get("PodDisruptionBudget", [])), f"{app}: PDB")
    # VPA só recomenda (Off): nunca reinicia pod nem disputa com o HPA.
    ok(any(v["spec"]["targetRef"]["name"] == svc and v["spec"]["updatePolicy"]["updateMode"] == "Off"
           for v in kinds.get("VerticalPodAutoscaler", [])), f"{app}: VPA em modo recomendação")
    ok(not any(n.startswith("AZURE_") for n in env), f"{app}: variável AZURE_ restante")
    ok(not str(c["image"]).startswith("acr-"), f"{app}: imagem ainda aponta para ACR")
    if app != "ngo":
        ok(env.get("CLOUD_PROVIDER", {}).get("value") == "gcp", f"{app}: CLOUD_PROVIDER != gcp")
        ref = env.get("GCP_PROJECT_ID", {}).get("valueFrom", {}).get("configMapKeyRef", {})
        ok(ref.get("name") == "gcp-config", f"{app}: GCP_PROJECT_ID não vem do gcp-config")
    if "HorizontalPodAutoscaler" in kinds:
        ok("replicas" not in dep["spec"], f"{app}: replicas fixo junto com HPA")
    if app in roteados:
        rotas = kinds.get("HTTPRoute", [])
        ok(len(rotas) == 1 and rotas[0]["spec"]["parentRefs"][0].get("sectionName") == "https", f"{app}: HTTPRoute no listener https")
        hcp = [h for h in kinds.get("HealthCheckPolicy", []) if h["spec"]["targetRef"]["name"] == svc]
        ok(hcp and hcp[0]["spec"]["default"]["config"]["httpHealthCheck"]["requestPath"] == "/health", f"{app}: HealthCheckPolicy /health")
    for job in kinds.get("Job", []):
        ann = job["metadata"].get("annotations", {})
        ok(ann.get("argocd.argoproj.io/hook") == "PreSync", f"{app}: Job {job['metadata']['name']} sem hook PreSync")
    for cm in kinds.get("ConfigMap", []):
        if cm["metadata"]["name"].startswith("db-init"):
            ok(cm["metadata"].get("annotations", {}).get("argocd.argoproj.io/sync-wave") == "-1", f"{app}: ConfigMap do db-init fora da onda -1")

# Applications e ApplicationSet: retry (o primeiro sync chega antes das CRDs)
# e, quando a fonte é Git, o próprio monorepo.
MONOREPO = "https://github.com/DemarchiWorking/solidary-tech-vale.git"
for f in sorted(G.rglob("*.yaml")):
    for d in docs(f):
        if d.get("kind") == "Application":
            sp = d["spec"]["syncPolicy"]
            ok("retry" in sp, f"{f.relative_to(RAIZ)}: Application sem retry")
            for s in d["spec"].get("sources", [d["spec"].get("source", {})]):
                if "github.com" in s.get("repoURL", ""):
                    ok(s["repoURL"] == MONOREPO, f"{f.relative_to(RAIZ)}: repoURL fora do monorepo")
        if d.get("kind") == "ApplicationSet":
            ok("retry" in d["spec"]["template"]["spec"]["syncPolicy"], "ApplicationSet sem retry")
            # deploy/gitops/apps/<app>/overlays/prod: o nome do app é o segmento 3.
            ok("index .path.segments 3" in f.read_text(encoding="utf-8"), "ApplicationSet: nome do app fora do segmento 3")

# Exposição só pelo Gateway: nenhum Ingress em nada que o ArgoCD aplica.
for f in sorted(RENDER.glob("*.yaml")):
    for d in docs(f):
        ok(d.get("kind") != "Ingress", f"{f.name}: Ingress {d.get('metadata', {}).get('name')}")

# Gateway.
gw = docs(G / "addons/gateway/manifests/gateway.yaml")[0]
ok(gw["spec"]["gatewayClassName"] == "gke-l7-global-external-managed", "Gateway: classe")
ok(gw["metadata"]["annotations"]["networking.gke.io/certmap"] == "solidarytech-gateway-certmap", "Gateway: certmap")
https = [l for l in gw["spec"]["listeners"] if l["name"] == "https"][0]
ok("tls" not in https, "Gateway: listener https não pode ter tls junto com certmap")
ok(gw["spec"]["addresses"][0]["value"] == "solidarytech-gateway-ip", "Gateway: IP nomeado")

# Nada de Azure/nginx no GitOps.
for f in sorted(G.rglob("*")):
    if f.is_file():
        t = f.read_text(encoding="utf-8", errors="ignore")
        for ruim in ("azure", "Azure", "AZURE", "ingressClassName", "nginx", "acr-nao-configurado", "cloud-credentials", "azure-secrets"):
            if ruim in t:
                falhas.append(f"{f.relative_to(RAIZ)}: contém '{ruim}'")

print("falhas: 0" if not falhas else "falhas:\n  - " + "\n  - ".join(falhas))
sys.exit(1 if falhas else 0)
