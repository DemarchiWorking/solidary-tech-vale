"""Checagens da documentação (README.md e docs/**):

- todo link relativo aponta para um arquivo que existe, e a âncora
  (#secao), quando há, para um título que existe nesse arquivo;
- todo caminho do repositório citado entre crases (`infra/...`,
  `modules/...`, `apps/...`) existe: é o que mantém o texto preso ao
  código. Caminhos com curinga ou marcador (`*`, `<`, `{`) e arquivos que
  só existem na main (`fiap-tc-5-*`) ficam de fora.

uso: python3 -P scripts/ci/checar_docs.py <raiz do repositório>
"""
import re
import sys
from pathlib import Path

RAIZ = Path(sys.argv[1]).resolve()
docs = [RAIZ / "README.md"] + sorted((RAIZ / "docs").rglob("*.md"))
falhas = []

LINK = re.compile(r"\]\(([^)\s]+)\)")
CRASE = re.compile(r"`([^`\n]+)`")
PREFIXOS = ("services/", "infra/", "deploy/", "scripts/", "docs/", ".github/", "modules/", "envs/",
            "bootstrap/", "apps/", "addons/", "applicationsets/")
BASES = [RAIZ, RAIZ / "infra/terraform", RAIZ / "deploy/gitops"]


def slug(titulo):
    # Mesmo algoritmo do GitHub: minúsculas, sem pontuação, espaço vira hífen.
    s = titulo.strip().lower()
    s = re.sub(r"[^\w\- ]", "", s, flags=re.UNICODE)
    return s.replace(" ", "-")


def ancoras(arq):
    texto = arq.read_text(encoding="utf-8")
    texto = re.sub(r"```.*?```", "", texto, flags=re.S)
    return {slug(m.group(1)) for m in re.finditer(r"^#{1,6} (.+)$", texto, flags=re.M)}


for md in docs:
    texto = md.read_text(encoding="utf-8")
    rel = md.relative_to(RAIZ)
    sem_codigo = re.sub(r"```.*?```", "", texto, flags=re.S)

    for alvo in LINK.findall(sem_codigo):
        if re.match(r"^[a-z]+://", alvo) or alvo.startswith("mailto:"):
            continue
        caminho, _, ancora = alvo.partition("#")
        destino = (md.parent / caminho).resolve() if caminho else md
        if not destino.exists():
            falhas.append(f"{rel}: link quebrado '{alvo}'")
            continue
        if ancora and destino.suffix == ".md" and ancora not in ancoras(destino):
            falhas.append(f"{rel}: âncora inexistente '{alvo}'")

    for token in CRASE.findall(sem_codigo):
        t = token.strip().split(":")[0].rstrip("/")
        if not t.startswith(PREFIXOS) or " " in t or any(c in t for c in "*<>{}$|"):
            continue
        if not any((b / t).exists() for b in BASES):
            falhas.append(f"{rel}: caminho citado não existe '{token}'")

print(f"{len(docs)} documentos; falhas: {len(falhas)}")
for f in falhas:
    print(f"  - {f}")
sys.exit(1 if falhas else 0)
