#!/usr/bin/env bash
# Todos os critérios de pronto da versão GCP num comando, sem nuvem, com as
# mesmas imagens e versões que o CI usa:
#
#   1. serviços    go vet, go test -race, golangci-lint; flake8 e pytest
#   2. imagens     docker build dos 4 serviços e Trivy (código e imagem, CRITICAL)
#   3. terraform   scripts/ci/terraform-check.sh
#   4. gitops      scripts/ci/gitops-check.sh
#   5. workflows   actionlint e scripts/ci/checar_workflows.py
#   6. docs        scripts/ci/checar_docs.py
#   7. e2e         docker compose up, scripts/smoke-local.sh, down -v
#
# uso:    bash scripts/validar.sh [etapa ...]     (sem argumento: todas)
# requer: docker, terraform 1.16+, kubectl, git, python3 com PyYAML
set -uo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ" || exit 2
ETAPAS=("$@")
[[ ${#ETAPAS[@]} -gt 0 ]] || ETAPAS=(servicos imagens terraform gitops workflows docs e2e)

caminho() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
dk() { MSYS_NO_PATHCONV=1 docker "$@"; }
PY=""
for c in python3 python; do
  if "$c" -c "import yaml" >/dev/null 2>&1; then PY="$c"; break; fi
done
[[ -n "$PY" ]] || { echo "precisa de python3 com PyYAML (pip install pyyaml)" >&2; exit 2; }

declare -A RESULTADO
falhou() { echo "  FALHOU: $*"; ETAPA_OK=0; }

servicos() {
  local d
  d="$(caminho "$RAIZ/services/donation-service")"
  dk run --rm -v "$d:/src:ro" -v gomodcache:/go/pkg/mod golang:1.26 sh -c \
    'cp -r /src /w && cd /w && go mod download && go vet ./... && go test -race -count=1 ./...' \
    && echo "  donation-service: vet e test -race ok" || falhou "donation-service go test"
  dk run --rm -v "$d:/src:ro" -v gomodcache:/go/pkg/mod golangci/golangci-lint:v2.15.0 sh -c \
    'cp -r /src /w && cd /w && golangci-lint run ./...' >/dev/null \
    && echo "  donation-service: golangci-lint ok" || falhou "donation-service golangci-lint"
  for s in ngo-service volunteer-service notification-service; do
    if dk run --rm -v "$(caminho "$RAIZ/services/$s"):/src:ro" -v pipcache:/root/.cache/pip python:3.12-slim sh -c \
      'cp -r /src /w && cd /w && pip install -q --root-user-action=ignore flake8 -r requirements.txt pytest >/dev/null 2>&1 &&
       flake8 . --max-line-length=120 --exclude="test_*.py" &&
       { pytest -q test_app.py > /tmp/pytest.log 2>&1; rc=$?; tail -1 /tmp/pytest.log; exit $rc; }'; then
      echo "  $s: flake8 e pytest ok"
    else
      falhou "$s flake8/pytest"
    fi
  done
}

imagens() {
  local t
  t="$(mktemp -d)"
  for s in donation-service ngo-service volunteer-service notification-service; do
    if ! docker build -q -t "validar/$s:local" "services/$s" >/dev/null; then falhou "docker build $s"; continue; fi
    docker save -o "$t/$s.tar" "validar/$s:local"
    if dk run --rm -v trivy-cache:/root/.cache/trivy -v "$(caminho "$t"):/img:ro" -v "$(caminho "$RAIZ/services/$s"):/src:ro" \
      --entrypoint sh aquasec/trivy:0.76.1 -c "trivy fs --quiet --severity CRITICAL --ignore-unfixed --exit-code 1 /src >/dev/null &&
        trivy image --quiet --severity CRITICAL --ignore-unfixed --exit-code 1 --input /img/$s.tar >/dev/null"; then
      echo "  $s: build ok, Trivy (código e imagem) sem CRITICAL, usuário $(docker image inspect -f '{{.Config.User}}' "validar/$s:local")"
    else
      falhou "Trivy $s"
    fi
  done
  rm -rf "$t"
}

terraform_() { bash scripts/ci/terraform-check.sh 2>&1 | grep -vE "^[│┌├└]|^Report Summary|^Legend|^- '|^$" || falhou "terraform-check"; }
gitops() { bash scripts/ci/gitops-check.sh || falhou "gitops-check"; }

workflows() {
  dk run --rm -v "$(caminho "$RAIZ"):/repo" -w /repo rhysd/actionlint:1.7.12 -no-color -oneline \
    && echo "  actionlint ok" || falhou "actionlint"
  "$PY" -P scripts/ci/checar_workflows.py "$RAIZ" | sed 's/^/  /' || falhou "checar_workflows"
}

docs_() { "$PY" -P scripts/ci/checar_docs.py "$RAIZ" | sed 's/^/  /' || falhou "checar_docs"; }

e2e() {
  if docker compose up -d --build --wait --wait-timeout 600 >/dev/null 2>&1 && bash scripts/smoke-local.sh; then
    echo "  e2e ok"
  else
    docker compose logs --no-color --tail=80
    falhou "e2e"
  fi
  docker compose down -v --remove-orphans >/dev/null 2>&1
}

for e in "${ETAPAS[@]}"; do
  echo "===== $e"
  ETAPA_OK=1
  inicio=$SECONDS
  case "$e" in
    servicos) servicos ;;
    imagens) imagens ;;
    terraform) terraform_ ;;
    gitops) gitops ;;
    workflows) workflows ;;
    docs) docs_ ;;
    e2e) e2e ;;
    *) echo "etapa desconhecida: $e" >&2; exit 2 ;;
  esac
  RESULTADO[$e]="$([[ $ETAPA_OK -eq 1 ]] && echo ok || echo FALHOU) ($((SECONDS - inicio)) s)"
done

echo
echo "===== resumo"
total=0
for e in "${ETAPAS[@]}"; do
  printf '  %-10s %s\n' "$e" "${RESULTADO[$e]}"
  [[ "${RESULTADO[$e]}" == ok* ]] || total=$((total + 1))
done
echo "etapas com falha: $total"
exit "$total"
