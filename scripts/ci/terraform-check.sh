#!/usr/bin/env bash
# Gate do Terraform sem nuvem: fmt, validate nas 6 raízes, terraform test
# (mock_provider) nos módulos e no bootstrap, tflint (ruleset google) e
# Trivy config. O mesmo script roda no CI (.github/workflows/terraform.yaml)
# e localmente (scripts/validar.sh).
#
# uso:    bash scripts/ci/terraform-check.sh
# requer: terraform 1.16+ e docker
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
TF="$RAIZ/infra/terraform"
RAIZES="bootstrap envs/prod/infra envs/prod/platform envs/prod/observability envs/dr/infra envs/dr/platform"

# Git Bash no Windows: o docker precisa do caminho no formato do Windows.
caminho() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
dk() { MSYS_NO_PATHCONV=1 docker "$@"; }

echo "== terraform fmt"
(cd "$TF" && terraform fmt -check -recursive -diff)
echo "  ok"

echo "== terraform validate"
for d in $RAIZES; do
  (cd "$TF/$d" && terraform init -backend=false -input=false -no-color >/dev/null)
  out=$(cd "$TF/$d" && terraform validate -no-color 2>&1) || { echo "$out"; exit 1; }
  echo "  $d: $(echo "$out" | grep -m1 -E "Success|Error")"
done

echo "== terraform test (mock_provider)"
for d in "$TF"/modules/* "$TF/bootstrap"; do
  [[ -d "$d/tests" ]] || continue
  (cd "$d" && terraform init -backend=false -input=false -no-color >/dev/null)
  out=$(cd "$d" && terraform test -no-color 2>&1) || { echo "$out"; exit 1; }
  echo "  ${d#"$TF"/}: $(echo "$out" | tail -1)"
done

echo "== tflint (recursive, ruleset google)"
# GITHUB_TOKEN (opcional) evita o limite de taxa ao baixar o plugin.
dk run --rm -e GITHUB_TOKEN -v "$(caminho "$TF"):/data" -w /data --entrypoint /bin/sh \
  ghcr.io/terraform-linters/tflint:v0.65.0 \
  -c 'tflint --init >/dev/null && tflint --recursive --config /data/.tflint.hcl --format compact'
echo "  ok"

echo "== trivy config (HIGH, CRITICAL)"
dk run --rm -v "$(caminho "$TF"):/src:ro" aquasec/trivy:0.76.1 \
  config --quiet --severity HIGH,CRITICAL --exit-code 1 --skip-dirs "**/.terraform" /src
echo "  ok"
