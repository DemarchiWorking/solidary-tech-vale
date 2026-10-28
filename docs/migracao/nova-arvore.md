# Nova árvore do monorepo

A `main` (e a `branch-azure`) guardam a versão Azure com as pastas herdadas
dos repositórios originais (`fiap-tc-5-*`). Na `branch-gcp` o monorepo foi
reorganizado por responsabilidade. Os movimentos foram feitos com `git mv`,
então o histórico de cada arquivo continua acessível com
`git log --follow`.

```
.
├── .github/workflows/        CI dos 4 serviços, self-heals, Terraform, GitOps, E2E
├── services/                 código dos microsserviços
│   ├── donation-service/     Go 1.26, Pub/Sub (ou Service Bus)
│   ├── ngo-service/          Python 3.12, Cloud SQL
│   ├── volunteer-service/    Python 3.12, Firestore (ou Cosmos DB Table)
│   └── notification-service/ Python 3.12, consumidor Pub/Sub -> Firestore
├── infra/terraform/          IaC do GCP
│   ├── bootstrap/            APIs, bucket do state, federação do GitHub, SAs do CI
│   ├── modules/              network, gke, data, workload-identity, edge, platform, observability
│   └── envs/                 prod/{infra,platform,observability} e dr/{infra,platform}
├── deploy/gitops/            o que o ArgoCD aplica (apps, addons, applicationsets)
├── scripts/                  ambiente local, smoke e gates do CI
├── docs/                     esta documentação
└── docker-compose.yml        ambiente local completo com os emuladores do GCP
```

## De onde veio cada arquivo da `main`

A tabela cobre os 108 arquivos versionados na `main` (`git ls-tree -r
main`) e foi gerada a partir do próprio Git, sem seleção manual. Quando o
destino é um caminho, o arquivo foi movido e, na maior parte dos casos,
adaptado ao GCP; o que mudou dentro de cada um está em
[inventario-azure-gcp.md](inventario-azure-gcp.md).

| Arquivo na `main` | Destino na `branch-gcp` |
|---|---|
| `.github/workflows/donation-service-ci.yaml` | `.github/workflows/donation-service-ci.yaml` |
| `.github/workflows/donation-service-self-heal.yml` | `.github/workflows/donation-service-self-heal.yml` |
| `.github/workflows/ngo-service-ci.yaml` | `.github/workflows/ngo-service-ci.yaml` |
| `.github/workflows/ngo-service-self-heal.yml` | `.github/workflows/ngo-service-self-heal.yml` |
| `.github/workflows/notification-service-ci.yaml` | `.github/workflows/notification-service-ci.yaml` |
| `.github/workflows/notification-service-self-heal.yml` | `.github/workflows/notification-service-self-heal.yml` |
| `.github/workflows/volunteer-service-ci.yaml` | `.github/workflows/volunteer-service-ci.yaml` |
| `.github/workflows/volunteer-service-self-heal.yml` | `.github/workflows/volunteer-service-self-heal.yml` |
| `fiap-tc-5-donation-service/.dockerignore` | `services/donation-service/.dockerignore` |
| `fiap-tc-5-donation-service/.gitignore` | `services/donation-service/.gitignore` |
| `fiap-tc-5-donation-service/Dockerfile` | `services/donation-service/Dockerfile` |
| `fiap-tc-5-donation-service/db/init.sql` | `services/donation-service/db/init.sql` |
| `fiap-tc-5-donation-service/go.mod` | `services/donation-service/go.mod` |
| `fiap-tc-5-donation-service/go.sum` | `services/donation-service/go.sum` |
| `fiap-tc-5-donation-service/handlers.go` | `services/donation-service/handlers.go` |
| `fiap-tc-5-donation-service/handlers_test.go` | `services/donation-service/handlers_test.go` |
| `fiap-tc-5-donation-service/main.go` | `services/donation-service/main.go` |
| `fiap-tc-5-donation-service/otel.go` | `services/donation-service/otel.go` |
| `fiap-tc-5-donation-service/queue.go` | `services/donation-service/queue.go` |
| `fiap-tc-5-donation-service/servicebus.go` | `services/donation-service/servicebus.go` |
| `fiap-tc-5-donation-service/sqs.go` | removido: caminho AWS (aws-sdk-go v1, sem suporte); ver ADR 0003 |
| `fiap-tc-5-donation-service/types.go` | `services/donation-service/types.go` |
| `fiap-tc-5-gitops/addons/grafana-dashboards/application.yaml` | `deploy/gitops/addons/grafana-dashboards/application.yaml` |
| `fiap-tc-5-gitops/addons/grafana-dashboards/kustomization.yaml` | `deploy/gitops/addons/grafana-dashboards/kustomization.yaml` |
| `fiap-tc-5-gitops/addons/grafana-dashboards/solidarytech-overview-dashboard.yaml` | `deploy/gitops/addons/grafana-dashboards/solidarytech-overview-dashboard.yaml` |
| `fiap-tc-5-gitops/addons/grafana-dashboards/solidarytech-sre-dashboard.yaml` | `deploy/gitops/addons/grafana-dashboards/solidarytech-sre-dashboard.yaml` |
| `fiap-tc-5-gitops/addons/kube-prometheus-stack/application.yaml` | `deploy/gitops/addons/kube-prometheus-stack/application.yaml` |
| `fiap-tc-5-gitops/addons/kube-prometheus-stack/grafana-ingress.yaml` | substituído por `deploy/gitops/addons/kube-prometheus-stack/grafana-route.yaml` (HTTPRoute) |
| `fiap-tc-5-gitops/addons/kube-prometheus-stack/values.yaml` | `deploy/gitops/addons/kube-prometheus-stack/values.yaml` |
| `fiap-tc-5-gitops/addons/kustomization.yaml` | `deploy/gitops/addons/kustomization.yaml` |
| `fiap-tc-5-gitops/addons/loki/application.yaml` | `deploy/gitops/addons/loki/application.yaml` |
| `fiap-tc-5-gitops/addons/loki/values.yaml` | `deploy/gitops/addons/loki/values.yaml` |
| `fiap-tc-5-gitops/addons/otel-collector-gateway/application.yaml` | `deploy/gitops/addons/otel-collector-gateway/application.yaml` |
| `fiap-tc-5-gitops/addons/otel-collector-gateway/values.yaml` | `deploy/gitops/addons/otel-collector-gateway/values.yaml` |
| `fiap-tc-5-gitops/addons/otel-collector-logs/application.yaml` | `deploy/gitops/addons/otel-collector-logs/application.yaml` |
| `fiap-tc-5-gitops/addons/otel-collector-logs/values.yaml` | `deploy/gitops/addons/otel-collector-logs/values.yaml` |
| `fiap-tc-5-gitops/addons/sonarqube/application.yaml` | `deploy/gitops/addons/sonarqube/application.yaml` |
| `fiap-tc-5-gitops/addons/sonarqube/ingress.yaml` | substituído por `deploy/gitops/addons/sonarqube/route.yaml` (HTTPRoute) |
| `fiap-tc-5-gitops/addons/sonarqube/values.yaml` | `deploy/gitops/addons/sonarqube/values.yaml` |
| `fiap-tc-5-gitops/addons/velero/application.yaml` | `deploy/gitops/addons/velero/application.yaml` |
| `fiap-tc-5-gitops/addons/velero/schedule.yaml` | `deploy/gitops/addons/velero/schedule.yaml` |
| `fiap-tc-5-gitops/addons/velero/values.yaml` | `deploy/gitops/addons/velero/values.yaml` |
| `fiap-tc-5-gitops/applicationsets/addons.yaml` | `deploy/gitops/applicationsets/addons.yaml` |
| `fiap-tc-5-gitops/applicationsets/apps-appset.yaml` | `deploy/gitops/applicationsets/apps-appset.yaml` |
| `fiap-tc-5-gitops/apps/donation/base/deployment.yaml` | `deploy/gitops/apps/donation/base/deployment.yaml` |
| `fiap-tc-5-gitops/apps/donation/base/kustomization.yaml` | `deploy/gitops/apps/donation/base/kustomization.yaml` |
| `fiap-tc-5-gitops/apps/donation/base/service.yaml` | `deploy/gitops/apps/donation/base/service.yaml` |
| `fiap-tc-5-gitops/apps/donation/overlays/prod/configmap.yaml` | `deploy/gitops/apps/donation/overlays/prod/configmap.yaml` |
| `fiap-tc-5-gitops/apps/donation/overlays/prod/db-init-job.yaml` | `deploy/gitops/apps/donation/overlays/prod/db-init-job.yaml` |
| `fiap-tc-5-gitops/apps/donation/overlays/prod/hpa.yaml` | `deploy/gitops/apps/donation/overlays/prod/hpa.yaml` |
| `fiap-tc-5-gitops/apps/donation/overlays/prod/ingress.yaml` | substituído por `deploy/gitops/apps/donation/overlays/prod/gateway.yaml` (HTTPRoute e políticas) |
| `fiap-tc-5-gitops/apps/donation/overlays/prod/kustomization.yaml` | `deploy/gitops/apps/donation/overlays/prod/kustomization.yaml` |
| `fiap-tc-5-gitops/apps/ngo/base/deployment.yaml` | `deploy/gitops/apps/ngo/base/deployment.yaml` |
| `fiap-tc-5-gitops/apps/ngo/base/kustomization.yaml` | `deploy/gitops/apps/ngo/base/kustomization.yaml` |
| `fiap-tc-5-gitops/apps/ngo/base/service.yaml` | `deploy/gitops/apps/ngo/base/service.yaml` |
| `fiap-tc-5-gitops/apps/ngo/overlays/prod/configmap.yaml` | `deploy/gitops/apps/ngo/overlays/prod/configmap.yaml` |
| `fiap-tc-5-gitops/apps/ngo/overlays/prod/db-init-job.yaml` | `deploy/gitops/apps/ngo/overlays/prod/db-init-job.yaml` |
| `fiap-tc-5-gitops/apps/ngo/overlays/prod/ingress.yaml` | substituído por `deploy/gitops/apps/ngo/overlays/prod/gateway.yaml` (HTTPRoute e políticas) |
| `fiap-tc-5-gitops/apps/ngo/overlays/prod/kustomization.yaml` | `deploy/gitops/apps/ngo/overlays/prod/kustomization.yaml` |
| `fiap-tc-5-gitops/apps/notification/base/deployment.yaml` | `deploy/gitops/apps/notification/base/deployment.yaml` |
| `fiap-tc-5-gitops/apps/notification/base/kustomization.yaml` | `deploy/gitops/apps/notification/base/kustomization.yaml` |
| `fiap-tc-5-gitops/apps/notification/base/service.yaml` | `deploy/gitops/apps/notification/base/service.yaml` |
| `fiap-tc-5-gitops/apps/notification/overlays/prod/kustomization.yaml` | `deploy/gitops/apps/notification/overlays/prod/kustomization.yaml` |
| `fiap-tc-5-gitops/apps/volunteer/base/deployment.yaml` | `deploy/gitops/apps/volunteer/base/deployment.yaml` |
| `fiap-tc-5-gitops/apps/volunteer/base/kustomization.yaml` | `deploy/gitops/apps/volunteer/base/kustomization.yaml` |
| `fiap-tc-5-gitops/apps/volunteer/base/service.yaml` | `deploy/gitops/apps/volunteer/base/service.yaml` |
| `fiap-tc-5-gitops/apps/volunteer/overlays/prod/ingress.yaml` | substituído por `deploy/gitops/apps/volunteer/overlays/prod/gateway.yaml` (HTTPRoute e políticas) |
| `fiap-tc-5-gitops/apps/volunteer/overlays/prod/kustomization.yaml` | `deploy/gitops/apps/volunteer/overlays/prod/kustomization.yaml` |
| `fiap-tc-5-gitops/bootstrap/app-of-apps.yaml` | removido: o app-of-apps agora é criado pelo Terraform (`modules/platform`, chart argocd-apps) |
| `fiap-tc-5-gitops/scripts/configurar-ambiente.sh` | `deploy/gitops/scripts/configurar-ambiente.sh` |
| `fiap-tc-5-ngo-service/.dockerignore` | `services/ngo-service/.dockerignore` |
| `fiap-tc-5-ngo-service/.gitignore` | `services/ngo-service/.gitignore` |
| `fiap-tc-5-ngo-service/Dockerfile` | `services/ngo-service/Dockerfile` |
| `fiap-tc-5-ngo-service/app.py` | `services/ngo-service/app.py` |
| `fiap-tc-5-ngo-service/db/init.sql` | `services/ngo-service/db/init.sql` |
| `fiap-tc-5-ngo-service/requirements.txt` | `services/ngo-service/requirements.txt` |
| `fiap-tc-5-ngo-service/test_app.py` | `services/ngo-service/test_app.py` |
| `fiap-tc-5-notification-service/.dockerignore` | `services/notification-service/.dockerignore` |
| `fiap-tc-5-notification-service/.gitignore` | `services/notification-service/.gitignore` |
| `fiap-tc-5-notification-service/Dockerfile` | `services/notification-service/Dockerfile` |
| `fiap-tc-5-notification-service/app.py` | `services/notification-service/app.py` |
| `fiap-tc-5-notification-service/requirements.txt` | `services/notification-service/requirements.txt` |
| `fiap-tc-5-notification-service/test_app.py` | `services/notification-service/test_app.py` |
| `fiap-tc-5-terraform/.gitignore` | sai da branch-gcp; equivale a `infra/terraform/.gitignore` |
| `fiap-tc-5-terraform/.terraform.lock.hcl` | sai da branch-gcp; equivale a um `.terraform.lock.hcl` por raiz e por módulo em `infra/terraform/` |
| `fiap-tc-5-terraform/aks.tf` | sai da branch-gcp; equivale a `modules/gke/main.tf` (cluster e pool) e `envs/prod/infra/main.tf` (Artifact Registry no lugar do ACR) |
| `fiap-tc-5-terraform/argocd.tf` | sai da branch-gcp; equivale a `modules/platform/main.tf` (ArgoCD e app-of-apps via argocd-apps) |
| `fiap-tc-5-terraform/backend.hcl.example` | sai da branch-gcp; equivale a `envs/*/*/backend.hcl.example` e `bootstrap/backend.tf.example` (state no GCS) |
| `fiap-tc-5-terraform/cosmosdb.tf` | sai da branch-gcp; equivale a `modules/data/main.tf` (Firestore) |
| `fiap-tc-5-terraform/datadog.tf` | sai da branch-gcp; equivale a `modules/observability/main.tf` |
| `fiap-tc-5-terraform/github_actions.tf` | sai da branch-gcp; equivale a `bootstrap/main.tf` (Workload Identity Federation e SAs do CI) |
| `fiap-tc-5-terraform/k8s-secrets.tf` | sai da branch-gcp; equivale a `modules/platform/main.tf` (Secrets e ConfigMap gcp-config) |
| `fiap-tc-5-terraform/main.tf` | sai da branch-gcp; equivale a `envs/prod/infra/main.tf` |
| `fiap-tc-5-terraform/network.tf` | sai da branch-gcp; equivale a `modules/network/main.tf` |
| `fiap-tc-5-terraform/outputs.tf` | sai da branch-gcp; equivale a `envs/prod/infra/outputs.tf` e `bootstrap/outputs.tf` |
| `fiap-tc-5-terraform/pagerduty.tf` | sai da branch-gcp; equivale a `modules/observability/main.tf` |
| `fiap-tc-5-terraform/postgresql.tf` | sai da branch-gcp; equivale a `modules/data/main.tf` (Cloud SQL) |
| `fiap-tc-5-terraform/providers.tf` | sai da branch-gcp; equivale a `versions.tf` de cada raiz |
| `fiap-tc-5-terraform/servicebus.tf` | sai da branch-gcp; equivale a `modules/data/main.tf` (Pub/Sub, DLQ e assinatura de inspeção) |
| `fiap-tc-5-terraform/terraform.tfvars.example` | sai da branch-gcp; equivale a `bootstrap/` e `envs/prod/{infra,platform,observability}/terraform.tfvars.example` |
| `fiap-tc-5-terraform/variables.tf` | sai da branch-gcp; equivale a `variables.tf` de cada raiz e de cada módulo |
| `fiap-tc-5-terraform/velero.tf` | sai da branch-gcp; equivale a `modules/workload-identity/main.tf` (GSA do Velero) e `modules/data/main.tf` (bucket de DR) |
| `fiap-tc-5-volunteer-service/.dockerignore` | `services/volunteer-service/.dockerignore` |
| `fiap-tc-5-volunteer-service/.gitignore` | `services/volunteer-service/.gitignore` |
| `fiap-tc-5-volunteer-service/Dockerfile` | `services/volunteer-service/Dockerfile` |
| `fiap-tc-5-volunteer-service/app.py` | `services/volunteer-service/app.py` |
| `fiap-tc-5-volunteer-service/requirements.txt` | `services/volunteer-service/requirements.txt` |
| `fiap-tc-5-volunteer-service/test_app.py` | `services/volunteer-service/test_app.py` |

## O que é novo na `branch-gcp`

Além dos movimentos acima, entram arquivos que não tinham equivalente:

- `infra/terraform/**`: a IaC do GCP inteira (bootstrap, 7 módulos com
  testes e 5 raízes de ambiente). A IaC Azure continua na `main` e na
  `branch-azure` (ver [ADR 0002](../arquitetura/adr/0002-monorepo-e-nova-arvore.md)).
- `deploy/gitops/addons/gateway/`, os `gateway.yaml` dos apps,
  `grafana-route.yaml`, `sonarqube/route.yaml` e
  `velero/volumesnapshotclass.yaml`: exposição pelo Gateway API e snapshots CSI.
- `deploy/gitops/apps/*/base/serviceaccount.yaml` e `pdb.yaml`: uma KSA por
  serviço (Workload Identity) e PodDisruptionBudget.
- `services/donation-service/pubsub.go`, `pubsub_test.go` e `main_test.go`:
  o adaptador Pub/Sub e os testes da seleção de backend.
- `docker-compose.yml`, `scripts/local/`, `scripts/smoke-local.sh`: o ambiente
  local com Postgres e os emuladores oficiais do Pub/Sub e do Firestore.
- `scripts/ci/`: os gates que o CI e o `scripts/validar.sh` rodam.
- `.github/workflows/terraform.yaml`, `gitops-validate.yaml` e
  `local-e2e.yaml`.
- `.gitattributes`: fim de linha LF em todo o repositório.
