#!/usr/bin/env bash
# Preenche os valores do ambiente que só existem depois do primeiro
# `terraform apply` de infra/terraform/envs/prod/infra: registry das
# imagens, hostname do Gateway (Grafana), bucket e GSA do Velero e a URL do
# banco do SonarQube. Atualiza pela chave, então pode rodar de novo (ex.:
# projeto recriado). Depois: revise o diff, commite e faça push; o ArgoCD
# aplica sozinho.
#
# uso:    ./scripts/configurar-ambiente.sh <pasta infra/terraform/envs/prod/infra>
# requer: terraform com acesso ao state (backend.hcl configurado)
set -euo pipefail

TF="${1:?uso: $0 <pasta infra/terraform/envs/prod/infra>}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"

out() { terraform -chdir="$TF" output -raw "$1"; }

REGISTRY="$(out registry_url)"
HOSTNAME_GW="$(out gateway_hostname)"
DR_BUCKET="$(out dr_bucket)"
VELERO_GSA="$(out velero_service_account)"
SONAR_JDBC="$(out sonarqube_jdbc_url)"

for v in REGISTRY HOSTNAME_GW DR_BUCKET VELERO_GSA SONAR_JDBC; do
  if [[ -z "${!v}" || "${!v}" == "null" ]]; then
    echo "valor vazio: $v (o apply de envs/prod/infra já terminou?)" >&2
    exit 1
  fi
done

# Registry das imagens: troca tudo antes do nome da imagem (o caminho do
# Artifact Registry tem três partes). O CI também atualiza a cada build.
for k in "$RAIZ"/apps/*/overlays/prod/kustomization.yaml; do
  sed -i -E "s|^(  newName: ).*/([^/]+)$|\1${REGISTRY}/\2|" "$k"
done

# Grafana atrás do Gateway: o domínio precisa ser o hostname público.
sed -i -E "s|^(      domain: ).*|\1\"${HOSTNAME_GW}\"|" "$RAIZ/addons/kube-prometheus-stack/values.yaml"

# Velero: bucket de DR e a GSA (anotação da KSA e assinatura de URLs).
sed -i -E \
  -e "s|^(      bucket: ).*|\1\"${DR_BUCKET}\"|" \
  -e "s|^(      iam\.gke\.io/gcp-service-account: ).*|\1\"${VELERO_GSA}\"|" \
  -e "s|^(        serviceAccount: ).*|\1\"${VELERO_GSA}\"|" \
  "$RAIZ/addons/velero/values.yaml"

# SonarQube: banco no Cloud SQL (IP privado).
sed -i -E "s|^(  jdbcUrl: ).*|\1\"${SONAR_JDBC}\"|" "$RAIZ/addons/sonarqube/values.yaml"

if grep -rqE "__[A-Z_]+__|registry-nao-configurado\.invalid" "$RAIZ/apps" "$RAIZ/addons"; then
  echo "ainda há valores sem preencher:" >&2
  grep -rnE "__[A-Z_]+__|registry-nao-configurado\.invalid" "$RAIZ/apps" "$RAIZ/addons" >&2
  exit 1
fi

git -C "$RAIZ" --no-pager diff --stat
echo "Revise o diff, commite e faça push: o ArgoCD aplica sozinho."
