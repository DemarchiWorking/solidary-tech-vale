# Inventário Azure -> GCP

## Serviços equivalentes

| Azure (`main`) | GCP (`branch-gcp`) | Onde está |
|---|---|---|
| AKS | GKE Standard regional, nós privados, endpoint DNS | `infra/terraform/modules/gke` |
| Azure Container Registry | Artifact Registry (tags imutáveis, limpeza automática) | `infra/terraform/envs/prod/infra/main.tf` |
| Azure Database for PostgreSQL | Cloud SQL PostgreSQL 15, HA regional, IP privado | `infra/terraform/modules/data/main.tf` |
| Service Bus (fila `donation-events`) | Pub/Sub (tópico, assinatura, DLQ e assinatura de inspeção) | `infra/terraform/modules/data/main.tf` |
| Cosmos DB (API Table) | Firestore nativo | `infra/terraform/modules/data/main.tf` |
| ingress-nginx + Load Balancer | Gateway API (`gke-l7-global-external-managed`) | `deploy/gitops/addons/gateway` |
| Certificado do ingress | Certificate Manager, host `<ip>.sslip.io` | `infra/terraform/modules/edge` |
| Service principal e `AZURE_CREDENTIALS` | Workload Identity Federation (GitHub) e Workload Identity (pods) | `infra/terraform/bootstrap`, `modules/workload-identity` |
| Blob Storage + Azure Disk no Velero | bucket GCS na região de DR + snapshots CSI | `deploy/gitops/addons/velero`, `modules/data` |
| Cost Management por tags | labels no billing e cost allocation do GKE | `envs/prod/infra/versions.tf` (`default_labels`) |

## Arquivos da `main` com identificadores Azure

Varredura de todos os arquivos da `main` pelos identificadores `azurerm`,
`azuread`, `azure*`, AKS, ACR, `azurecr`, Service Bus, Cosmos, `AZURE_*`,
`az <comando>` e os clientes de Table Storage. São 46 arquivos e todos
estão abaixo; a lista foi gerada pela mesma expressão regular usada na
checagem final, então não há arquivo de fora.

| Arquivo na `main` | O que tinha de Azure | O que virou na `branch-gcp` |
|---|---|---|
| `.github/workflows/donation-service-ci.yaml` | login no ACR com usuário e senha (`ACR_USERNAME`/`ACR_PASSWORD`), imagem `<acr>.azurecr.io` | Artifact Registry com Workload Identity Federation (`google-github-actions/auth` v3, SA ci-deployer), só a tag do commit (tags imutáveis), Go 1.26 e Python 3.12 |
| `.github/workflows/donation-service-self-heal.yml` | `azure/login` com `AZURE_CREDENTIALS` e `az aks get-credentials` | federação para a SA ci-selfheal, `get-gke-credentials` v3 pelo endpoint DNS, título do alerta só por variável de ambiente, concurrency por serviço |
| `.github/workflows/ngo-service-ci.yaml` | login no ACR com usuário e senha (`ACR_USERNAME`/`ACR_PASSWORD`), imagem `<acr>.azurecr.io` | Artifact Registry com Workload Identity Federation (`google-github-actions/auth` v3, SA ci-deployer), só a tag do commit (tags imutáveis), Go 1.26 e Python 3.12 |
| `.github/workflows/ngo-service-self-heal.yml` | `azure/login` com `AZURE_CREDENTIALS` e `az aks get-credentials` | federação para a SA ci-selfheal, `get-gke-credentials` v3 pelo endpoint DNS, título do alerta só por variável de ambiente, concurrency por serviço |
| `.github/workflows/notification-service-ci.yaml` | login no ACR com usuário e senha (`ACR_USERNAME`/`ACR_PASSWORD`), imagem `<acr>.azurecr.io` | Artifact Registry com Workload Identity Federation (`google-github-actions/auth` v3, SA ci-deployer), só a tag do commit (tags imutáveis), Go 1.26 e Python 3.12 |
| `.github/workflows/notification-service-self-heal.yml` | `azure/login` com `AZURE_CREDENTIALS` e `az aks get-credentials` | federação para a SA ci-selfheal, `get-gke-credentials` v3 pelo endpoint DNS, título do alerta só por variável de ambiente, concurrency por serviço |
| `.github/workflows/volunteer-service-ci.yaml` | login no ACR com usuário e senha (`ACR_USERNAME`/`ACR_PASSWORD`), imagem `<acr>.azurecr.io` | Artifact Registry com Workload Identity Federation (`google-github-actions/auth` v3, SA ci-deployer), só a tag do commit (tags imutáveis), Go 1.26 e Python 3.12 |
| `.github/workflows/volunteer-service-self-heal.yml` | `azure/login` com `AZURE_CREDENTIALS` e `az aks get-credentials` | federação para a SA ci-selfheal, `get-gke-credentials` v3 pelo endpoint DNS, título do alerta só por variável de ambiente, concurrency por serviço |
| `fiap-tc-5-donation-service/go.mod` | SDK do Service Bus e aws-sdk-go v1 | `cloud.google.com/go/pubsub/v2` v2.8.0 e `go 1.26.0`; Service Bus mantido como adaptador; aws-sdk-go removido |
| `fiap-tc-5-donation-service/go.sum` | hashes do SDK Azure e da AWS | regerado com `go mod tidy` (hashes do Pub/Sub; Azure só o que o adaptador usa) |
| `fiap-tc-5-donation-service/main.go` | `log.Fatal` no servidor e Service Bus ou SQS escolhidos por variáveis | `CLOUD_PROVIDER` (`gcp` padrão, `azure`, `none`), desligamento gracioso com `http.Server` e `signal.NotifyContext` |
| `fiap-tc-5-donation-service/servicebus.go` | envio síncrono ao Service Bus | mantido como adaptador `azure`, com `MessageID` = `event_id` e `Close` que espera os envios |
| `fiap-tc-5-donation-service/sqs.go` | caminho AWS SQS | removido |
| `fiap-tc-5-gitops/addons/grafana-dashboards/solidarytech-overview-dashboard.yaml` | texto citando AKS | texto ajustado para GKE |
| `fiap-tc-5-gitops/addons/kube-prometheus-stack/values.yaml` | comentários de AKS e domínio do ingress | comentários de GKE, `domain` preenchido com o host sslip.io pelo `configurar-ambiente.sh` |
| `fiap-tc-5-gitops/addons/velero/values.yaml` | plugin Azure, Blob Storage, Azure Disk e `__AZURE_SUBSCRIPTION_ID__` | `velero-plugin-for-gcp` v1.14.4, bucket de DR no GCS, Workload Identity na KSA `velero-server`, snapshots só via CSI |
| `fiap-tc-5-gitops/apps/donation/base/deployment.yaml` | Secret `azure-secrets` com a connection string do Service Bus | `CLOUD_PROVIDER=gcp`, `GCP_PROJECT_ID` do ConfigMap `gcp-config`, `PUBSUB_TOPIC`, KSA própria, preStop, topology spread |
| `fiap-tc-5-gitops/apps/donation/overlays/prod/kustomization.yaml` | imagem `acr-nao-configurado.invalid/...` | imagem `registry-nao-configurado.invalid/...` até o CI ou o `configurar-ambiente.sh` gravarem o Artifact Registry; Ingress trocado por `gateway.yaml` |
| `fiap-tc-5-gitops/apps/ngo/overlays/prod/kustomization.yaml` | imagem `acr-nao-configurado.invalid/...` | imagem `registry-nao-configurado.invalid/...` até o CI ou o `configurar-ambiente.sh` gravarem o Artifact Registry; Ingress trocado por `gateway.yaml` |
| `fiap-tc-5-gitops/apps/notification/base/deployment.yaml` | Secret `azure-secrets` com Service Bus e Cosmos DB | `CLOUD_PROVIDER=gcp`, assinatura Pub/Sub e coleção do Firestore, KSA própria |
| `fiap-tc-5-gitops/apps/notification/overlays/prod/kustomization.yaml` | imagem `acr-nao-configurado.invalid/...` | imagem `registry-nao-configurado.invalid/...` até o CI ou o `configurar-ambiente.sh` gravarem o Artifact Registry; Ingress trocado por `gateway.yaml` |
| `fiap-tc-5-gitops/apps/volunteer/base/deployment.yaml` | Secret `azure-secrets` com Cosmos DB | `CLOUD_PROVIDER=gcp`, coleção `volunteers` no Firestore, KSA própria |
| `fiap-tc-5-gitops/apps/volunteer/overlays/prod/kustomization.yaml` | imagem `acr-nao-configurado.invalid/...` | imagem `registry-nao-configurado.invalid/...` até o CI ou o `configurar-ambiente.sh` gravarem o Artifact Registry; Ingress trocado por `gateway.yaml` |
| `fiap-tc-5-gitops/scripts/configurar-ambiente.sh` | `az aks`/`az acr` para descobrir ACR e cluster | lê os outputs de `envs/prod/infra` (registry, hostname, bucket, GSA do Velero, JDBC do SonarQube) e atualiza pela chave, idempotente |
| `fiap-tc-5-notification-service/app.py` | Service Bus com `complete` incondicional e gravação no Cosmos DB Table | Pub/Sub com ack só depois de gravar e nack no erro (DLQ), Firestore idempotente por `event_id`; adaptador Azure mantido, agora com `abandon` no erro |
| `fiap-tc-5-notification-service/requirements.txt` | `azure-servicebus`, `azure-data-tables` | mais `google-cloud-pubsub` 2.43.0 e `google-cloud-firestore` 2.34.1; dependências atualizadas |
| `fiap-tc-5-notification-service/test_app.py` | testes só do caminho Azure | 15 testes: núcleo, consumidor GCP (ack/nack) e Azure (complete/abandon) |
| `fiap-tc-5-terraform/.terraform.lock.hcl` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a um `.terraform.lock.hcl` por raiz e por módulo em `infra/terraform/` |
| `fiap-tc-5-terraform/aks.tf` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `modules/gke/main.tf` (cluster e pool) e `envs/prod/infra/main.tf` (Artifact Registry no lugar do ACR) |
| `fiap-tc-5-terraform/argocd.tf` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `modules/platform/main.tf` (ArgoCD e app-of-apps via argocd-apps) |
| `fiap-tc-5-terraform/backend.hcl.example` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `envs/*/*/backend.hcl.example` e `bootstrap/backend.tf.example` (state no GCS) |
| `fiap-tc-5-terraform/cosmosdb.tf` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `modules/data/main.tf` (Firestore) |
| `fiap-tc-5-terraform/datadog.tf` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `modules/observability/main.tf` |
| `fiap-tc-5-terraform/github_actions.tf` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `bootstrap/main.tf` (Workload Identity Federation e SAs do CI) |
| `fiap-tc-5-terraform/k8s-secrets.tf` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `modules/platform/main.tf` (Secrets e ConfigMap gcp-config) |
| `fiap-tc-5-terraform/main.tf` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `envs/prod/infra/main.tf` |
| `fiap-tc-5-terraform/network.tf` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `modules/network/main.tf` |
| `fiap-tc-5-terraform/outputs.tf` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `envs/prod/infra/outputs.tf` e `bootstrap/outputs.tf` |
| `fiap-tc-5-terraform/postgresql.tf` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `modules/data/main.tf` (Cloud SQL) |
| `fiap-tc-5-terraform/providers.tf` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `versions.tf` de cada raiz |
| `fiap-tc-5-terraform/servicebus.tf` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `modules/data/main.tf` (Pub/Sub, DLQ e assinatura de inspeção) |
| `fiap-tc-5-terraform/terraform.tfvars.example` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `bootstrap/` e `envs/prod/{infra,platform,observability}/terraform.tfvars.example` |
| `fiap-tc-5-terraform/variables.tf` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `variables.tf` de cada raiz e de cada módulo |
| `fiap-tc-5-terraform/velero.tf` | recursos `azurerm`/`azuread` | sai da branch-gcp; equivale a `modules/workload-identity/main.tf` (GSA do Velero) e `modules/data/main.tf` (bucket de DR) |
| `fiap-tc-5-volunteer-service/app.py` | Cosmos DB Table (Azure) ou DynamoDB (AWS) | Firestore (`gcp`, padrão) ou Cosmos DB Table (`azure`); AWS removido; provedor inválido encerra o processo |
| `fiap-tc-5-volunteer-service/requirements.txt` | `azure-data-tables` e boto3 | `google-cloud-firestore` 2.34.1 e `azure-data-tables`; boto3 removido |

## O que continua com Azure na `branch-gcp`, de propósito

- Adaptadores dos serviços, selecionados por `CLOUD_PROVIDER=azure`:
  `services/donation-service/servicebus.go` (e o SDK no `go.mod`),
  `services/volunteer-service/app.py` e `services/notification-service/app.py`
  (e `azure-data-tables`/`azure-servicebus` nos `requirements.txt`), com os
  testes de cada um. O padrão é `gcp` em todos (ver
  [ADR 0003](../arquitetura/adr/0003-adaptadores-por-cloud-provider.md)).
- As checagens que procuram restos da versão Azure
  (`scripts/ci/checar_gitops.py` e `scripts/ci/checar_workflows.py`) citam os
  padrões que procuram.
- Dois comentários de paridade em `infra/terraform/modules/data/` (o limite de
  10 entregas é o mesmo `max_delivery_count` do Service Bus).

Nenhum manifesto do GitOps, workflow ou arquivo de Terraform da `branch-gcp`
depende de recurso Azure; isso é verificado no CI por
`scripts/ci/checar_gitops.py` e `scripts/ci/checar_workflows.py`.
