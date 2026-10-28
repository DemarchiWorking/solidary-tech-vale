"""Checagens estruturais dos workflows (complementa o actionlint):

- toda action fixada por SHA de 40 caracteres;
- job que usa google-github-actions/auth tem id-token: write;
- caminhos citados (working-directory, GITOPS_APP_PATH, paths, scripts)
  existem no repositório;
- dado de fora (client_payload, títulos de PR/issue) nunca interpolado
  direto num `run:`;
- nenhum resto da versão Azure (azure/*, ACR_*, AKS_*);
- nenhum `run:` antes do checkout com working-directory numa pasta do
  repositório (antes do checkout só existe a raiz do workspace, e o bash
  nem chega a iniciar).

uso: python3 -P scripts/ci/checar_workflows.py <raiz do repositório>
requer: PyYAML
"""
import re
import sys
from pathlib import Path

import yaml

RAIZ = Path(sys.argv[1])
WF = RAIZ / ".github/workflows"
falhas = []

SHA = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")
NAO_CONFIAVEL = re.compile(r"\$\{\{\s*github\.event\.(client_payload|pull_request\.(title|body)|issue\.|comment\.|head_commit\.message)")
AZURE = re.compile(r"azure/|ACR_|AKS_|AZURE_|azurecr\.io")


def existe(caminho, origem):
    base = caminho.split("*")[0].rstrip("/")
    if base and not (RAIZ / base).exists():
        falhas.append(f"{origem}: caminho inexistente '{caminho}'")


arquivos = sorted(list(WF.glob("*.yaml")) + list(WF.glob("*.yml")))
for f in arquivos:
    nome = f.name
    texto = f.read_text(encoding="utf-8")
    wf = yaml.safe_load(texto)
    # O YAML lê a chave "on" como True.
    gatilhos = wf.get("on", wf.get(True, {})) or {}

    for m in AZURE.finditer(texto):
        falhas.append(f"{nome}: resto da versão Azure '{m.group(0)}'")

    for evento in ("push", "pull_request"):
        for p in (gatilhos.get(evento) or {}).get("paths", []):
            existe(p, f"{nome} on.{evento}.paths")

    perm_wf = wf.get("permissions", {}) or {}
    wd_wf = ((wf.get("defaults") or {}).get("run") or {}).get("working-directory")
    if wd_wf:
        existe(wd_wf, f"{nome} defaults")
    for k, v in (wf.get("env") or {}).items():
        if k.endswith("_PATH") and isinstance(v, str):
            existe(v, f"{nome} env.{k}")

    for job_id, job in wf["jobs"].items():
        perm = job.get("permissions", perm_wf) or {}
        wd_job = ((job.get("defaults") or {}).get("run") or {}).get("working-directory", wd_wf)
        usa_auth = False
        fez_checkout = False
        for passo in job.get("steps", []):
            uses = passo.get("uses")
            if uses:
                if not SHA.match(uses):
                    falhas.append(f"{nome}/{job_id}: action sem SHA '{uses}'")
                if uses.startswith("google-github-actions/auth@"):
                    usa_auth = True
                if uses.startswith("actions/checkout@"):
                    fez_checkout = True
            run = passo.get("run")
            if run:
                wd_passo = passo.get("working-directory", wd_job)
                if not fez_checkout and wd_passo not in (None, ".", ""):
                    falhas.append(f"{nome}/{job_id}: '{passo.get('name')}' roda em '{wd_passo}' antes do checkout")
                if NAO_CONFIAVEL.search(run):
                    falhas.append(f"{nome}/{job_id}: dado de fora interpolado no run ('{passo.get('name')}')")
                for s in re.findall(r"bash (scripts/[\w./-]+\.sh)", run):
                    existe(s, f"{nome}/{job_id}")
            wd = passo.get("working-directory", wd_job)
            if wd and wd != ".":
                existe(wd, f"{nome}/{job_id} working-directory")
        if usa_auth and perm.get("id-token") != "write":
            falhas.append(f"{nome}/{job_id}: usa auth do GCP sem id-token: write")

print(f"{len(arquivos)} workflows; falhas: {len(falhas)}")
for x in falhas:
    print(f"  - {x}")
sys.exit(1 if falhas else 0)
