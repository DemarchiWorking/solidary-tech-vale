#!/usr/bin/env bash
# Preenche os valores do ambiente que só existem depois do primeiro
# `terraform apply`: registry das imagens, Velero e domínio do Grafana.
# Atualiza pela chave, então pode rodar de novo (ex.: cluster recriado).
#
# uso:    ./scripts/configurar-ambiente.sh <pasta do fiap-tc-5-terraform>
# requer: terraform com acesso ao state e kubectl apontando para o AKS
#         (az aks get-credentials ...)
set -euo pipefail

TF="${1:?uso: $0 <pasta do fiap-tc-5-terraform>}"
RAIZ="$(cd "$(dirname "$0")/.." && pwd)"

out() { terraform -chdir="$TF" output -raw "$1"; }

ACR="$(out acr_admin_username)"
RG="$(out resource_group_name)"
NODE_RG="$(out aks_node_resource_group)"
SUB="$(out subscription_id)"
VELERO_SA="$(out velero_storage_account_name)"
IP="$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"

for v in ACR RG NODE_RG SUB VELERO_SA IP; do
  if [[ -z "${!v}" || "${!v}" == "null" ]]; then
    echo "valor vazio: $v (o apply com deploy_databases = true já terminou? o ingress já tem IP?)" >&2
    exit 1
  fi
done

# Registry das imagens. O CI de cada serviço também atualiza a cada build.
for k in "$RAIZ"/apps/*/overlays/prod/kustomization.yaml; do
  sed -i -E "s|^(  newName: )[^/]+/|\1${ACR}.azurecr.io/|" "$k"
done

# Velero: o backup vai para o storage do resource group principal; os
# snapshots de disco ficam no resource group gerenciado pelo AKS (MC_...).
sed -i -E \
  -e "/backupStorageLocation:/,/volumeSnapshotLocation:/ s|^(        resourceGroup: ).*|\1\"${RG}\"|" \
  -e "/volumeSnapshotLocation:/,\$ s|^(        resourceGroup: ).*|\1\"${NODE_RG}\"|" \
  -e "s|^(        storageAccount: ).*|\1\"${VELERO_SA}\"|" \
  -e "s|^(        subscriptionId: ).*|\1\"${SUB}\"|" \
  "$RAIZ/addons/velero/values.yaml"

# Grafana atrás do ingress: o domínio precisa ser o IP público do
# LoadBalancer, senão o redirect cai em localhost.
sed -i -E "s|^(      domain: ).*|\1\"${IP}\"|" "$RAIZ/addons/kube-prometheus-stack/values.yaml"

if grep -rqE "__[A-Z_]+__|acr-nao-configurado\.invalid" "$RAIZ/apps" "$RAIZ/addons"; then
  echo "ainda há valores sem preencher:" >&2
  grep -rnE "__[A-Z_]+__|acr-nao-configurado\.invalid" "$RAIZ/apps" "$RAIZ/addons" >&2
  exit 1
fi

git -C "$RAIZ" --no-pager diff --stat
echo "Revise o diff, commite e faça push: o ArgoCD aplica sozinho."
