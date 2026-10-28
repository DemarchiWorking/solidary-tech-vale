#!/usr/bin/env bash
# Gate do GitOps sem cluster: render (kustomize e helm template com os
# values do repositório), kubeconform estrito com o catálogo de CRDs,
# checagens estruturais (scripts/ci/checar_gitops.py), o
# configurar-ambiente.sh rodando duas vezes com um terraform falso e o
# lint dos scripts. O mesmo script roda no CI
# (.github/workflows/gitops-validate.yaml) e localmente (scripts/validar.sh).
#
# uso:    bash scripts/ci/gitops-check.sh
# requer: kubectl, docker, git, python3 com PyYAML
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
G="$RAIZ/deploy/gitops"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
FALHAS=0
falhou() { echo "  FALHOU: $*"; FALHAS=$((FALHAS + 1)); }

# Git Bash no Windows: o docker precisa do caminho no formato do Windows.
caminho() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
dk() { MSYS_NO_PATHCONV=1 docker "$@"; }

PY=""
for c in python3 python; do
  if "$c" -c "import yaml" >/dev/null 2>&1; then PY="$c"; break; fi
done
[[ -n "$PY" ]] || { echo "precisa de python3 com PyYAML (pip install pyyaml)" >&2; exit 2; }

# Catálogo de schemas das CRDs (Gateway API, GKE, ArgoCD, Velero,
# Prometheus Operator, snapshot.storage), fixado num commit.
CATALOGO='https://raw.githubusercontent.com/datreeio/CRDs-catalog/3eb90d47aba8d61919d4419dd38301536e32a94b/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

echo "== kustomize build"
for a in donation ngo volunteer notification; do
  kubectl kustomize "$G/apps/$a/overlays/prod" > "$OUT/app-$a.yaml" || falhou "kustomize $a"
done
kubectl kustomize "$G/addons" > "$OUT/addons-apps.yaml" || falhou "kustomize addons"
kubectl kustomize "$G/addons/grafana-dashboards" > "$OUT/dashboards.yaml" || falhou "kustomize dashboards"
# Diretórios que o ArgoCD aplica como manifests puros (directory/include).
for f in "$G"/addons/gateway/manifests/*.yaml "$G/addons/kube-prometheus-stack/grafana-route.yaml" \
  "$G/addons/sonarqube/route.yaml" "$G/addons/velero/schedule.yaml" "$G/addons/velero/volumesnapshotclass.yaml" \
  "$G"/applicationsets/*.yaml; do
  echo "---"; cat "$f"
done > "$OUT/manifests.yaml"
echo "  $(ls "$OUT" | wc -l) arquivos renderizados"

echo "== helm template dos addons (charts e versões das Applications)"
helm_t() { # nome repo chart versão values [namespace]
  if dk run --rm -v "$(caminho "$G"):/g:ro" alpine/helm:3.19.0 template "$1" "$3" --repo "$2" --version "$4" \
    --namespace "${6:-monitoring}" -f "/g/$5" > "$OUT/helm-$1.yaml" 2> "$OUT/helm-$1.err"; then
    echo "  $1 ($3 $4): $(grep -c '^kind:' "$OUT/helm-$1.yaml") objetos"
  else
    tail -5 "$OUT/helm-$1.err"; falhou "helm $1"
  fi
  rm -f "$OUT/helm-$1.err"
}
helm_t kube-prometheus-stack https://prometheus-community.github.io/helm-charts kube-prometheus-stack 90.0.0 addons/kube-prometheus-stack/values.yaml
helm_t loki https://grafana.github.io/helm-charts loki 7.3.0 addons/loki/values.yaml
helm_t otel-collector https://open-telemetry.github.io/opentelemetry-helm-charts opentelemetry-collector 0.173.0 addons/otel-collector-gateway/values.yaml
helm_t otel-collector-logs https://open-telemetry.github.io/opentelemetry-helm-charts opentelemetry-collector 0.173.0 addons/otel-collector-logs/values.yaml
helm_t sonarqube https://SonarSource.github.io/helm-chart-sonarqube sonarqube 2026.4.1 addons/sonarqube/values.yaml sonarqube
helm_t velero https://vmware-tanzu.github.io/helm-charts velero 12.1.0 addons/velero/values.yaml velero

echo "== conferências nos charts renderizados"
confere() { # arquivo padrão mensagem
  if grep -q "$2" "$OUT/$1"; then echo "  $3"; else falhou "$3"; fi
}
nao_tem() { # arquivo padrão mensagem
  if grep -q "$2" "$OUT/$1"; then falhou "$3"; else echo "  $3"; fi
}
confere helm-velero.yaml "velero-plugin-for-gcp:v1.14.4" "velero: plugin gcp v1.14.4"
confere helm-velero.yaml "iam.gke.io/gcp-service-account" "velero: KSA anotada (Workload Identity)"
confere helm-velero.yaml "provider: gcp" "velero: BackupStorageLocation gcp"
nao_tem helm-velero.yaml "kind: VolumeSnapshotLocation" "velero: sem VolumeSnapshotLocation nativo (só CSI)"
confere helm-sonarqube.yaml "/sonarqube" "sonarqube: web context /sonarqube"
confere helm-sonarqube.yaml "sonarqube-jdbc" "sonarqube: senha do banco via Secret"
nao_tem helm-sonarqube.yaml "bitnami/postgresql" "sonarqube: sem Postgres embutido"
confere helm-kube-prometheus-stack.yaml "grafana-admin" "grafana: admin via Secret"

echo "== kubeconform (estrito, catálogo de CRDs)"
for f in "$OUT"/*.yaml; do
  res=$(dk run --rm -v "$(caminho "$OUT"):/r:ro" ghcr.io/yannh/kubeconform:v0.8.0 -strict -summary \
    -schema-location default -schema-location "$CATALOGO" "/r/$(basename "$f")" 2>&1)
  if echo "$res" | grep -q "Invalid: 0, Errors: 0"; then
    echo "  $(basename "$f"): $(echo "$res" | grep -oE 'Valid: [0-9]+, Invalid: 0, Errors: 0, Skipped: [0-9]+')"
  else
    echo "$res" | tail -8; falhou "kubeconform $(basename "$f")"
  fi
done

echo "== checagens estruturais"
"$PY" -P "$RAIZ/scripts/ci/checar_gitops.py" "$RAIZ" "$OUT" | sed 's/^/  /' || falhou "checagens estruturais"

echo "== db-init (hook PreSync) duas vezes num PostgreSQL 15"
# O Job roda antes de todo sync, com ON_ERROR_STOP=1: o SQL precisa poder
# rodar de novo num banco que já tem as tabelas e os dados iniciais.
mkdir -p "$OUT/sql"
"$PY" -P - "$OUT" <<'EOF'
import sys, pathlib, yaml
out = pathlib.Path(sys.argv[1])
for f in sorted(out.glob("app-*.yaml")):
    for d in yaml.safe_load_all(f.read_text(encoding="utf-8")):
        if isinstance(d, dict) and d.get("kind") == "ConfigMap" and d["metadata"]["name"].startswith("db-init"):
            (out / "sql" / (d["metadata"]["name"] + ".sql")).write_text(d["data"]["init.sql"], encoding="utf-8")
EOF
PG="tc5-dbinit-$$"
dk run -d --rm --name "$PG" -e POSTGRES_PASSWORD=ci -v "$(caminho "$OUT/sql"):/sql:ro" postgres:15-alpine >/dev/null
for _ in $(seq 1 30); do dk exec "$PG" pg_isready -U postgres -q 2>/dev/null && break; sleep 1; done
sleep 2
for s in "$OUT"/sql/*.sql; do
  n=$(basename "$s")
  if dk exec -e PGOPTIONS="-c client_min_messages=warning" "$PG" psql -q -v ON_ERROR_STOP=1 -U postgres -f "/sql/$n" >/dev/null &&
     dk exec -e PGOPTIONS="-c client_min_messages=warning" "$PG" psql -q -v ON_ERROR_STOP=1 -U postgres -f "/sql/$n" >/dev/null; then
    echo "  $n: 2 execuções sem erro"
  else
    falhou "db-init $n não pode rodar duas vezes"
  fi
done
echo "  linhas em ngos depois de 2 execuções: $(dk exec "$PG" psql -tA -U postgres -c 'select count(*) from ngos' 2>/dev/null)"
dk rm -f "$PG" >/dev/null 2>&1

echo "== configurar-ambiente.sh com terraform falso (2x, idempotente)"
W="$(mktemp -d)"
mkdir -p "$W/bin" "$W/tf"
cp -r "$G" "$W/gitops"
git -C "$W/gitops" init -q
git -C "$W/gitops" config core.autocrlf false
git -C "$W/gitops" add -A
git -C "$W/gitops" -c user.name=ci -c user.email=ci@example.invalid commit -qm base
cat > "$W/bin/terraform" <<'EOF'
#!/usr/bin/env bash
case "${*: -1}" in
  registry_url) printf southamerica-east1-docker.pkg.dev/proj-teste/solidarytech ;;
  gateway_hostname) printf 34-95-10-20.sslip.io ;;
  dr_bucket) printf proj-teste-solidarytech-dr ;;
  velero_service_account) printf solidarytech-velero@proj-teste.iam.gserviceaccount.com ;;
  sonarqube_jdbc_url) printf 'jdbc:postgresql://10.40.0.5:5432/sonarqube?sslmode=require' ;;
esac
EOF
chmod +x "$W/bin/terraform"
roda() { PATH="$W/bin:$PATH" bash "$W/gitops/scripts/configurar-ambiente.sh" "$W/tf" >/dev/null 2>&1; }
roda || falhou "configurar-ambiente: 1a execução"
d1=$(git -C "$W/gitops" diff)
roda || falhou "configurar-ambiente: 2a execução"
d2=$(git -C "$W/gitops" diff)
if [[ -n "$d1" && "$d1" == "$d2" ]]; then
  echo "  idempotente ($(git -C "$W/gitops" diff --stat | tail -1 | sed 's/^ *//'))"
else
  falhou "configurar-ambiente não é idempotente (ou não mudou nada)"
fi
if grep -rqE "__[A-Z_]+__|registry-nao-configurado" "$W/gitops/apps" "$W/gitops/addons"; then
  falhou "configurar-ambiente deixou placeholders"
fi
rm -rf "$W"

echo "== shellcheck"
if dk run --rm -v "$(caminho "$RAIZ"):/r:ro" koalaman/shellcheck:v0.11.0 -S warning \
  /r/deploy/gitops/scripts/configurar-ambiente.sh /r/scripts/smoke-local.sh \
  /r/scripts/local/postgres-init.sh /r/scripts/local/pubsub-init.sh \
  /r/scripts/ci/terraform-check.sh /r/scripts/ci/gitops-check.sh /r/scripts/validar.sh; then
  echo "  ok"
else
  falhou "shellcheck"
fi

echo
echo "falhas: $FALHAS"
exit "$FALHAS"
