# ADR 0007. Identidade sem chave: Workload Identity e Workload Identity Federation

Status: aceita (branch-gcp)

## Contexto

Na `main`, os pods recebiam connection strings num Secret `azure-secrets` e
o GitHub Actions entrava com `AZURE_CREDENTIALS` (service principal com
segredo) e usuário e senha de admin do ACR.

## Decisão

Nenhuma chave de service account é criada.

Pods: cada serviço roda com a sua KSA
(`deploy/gitops/apps/*/base/serviceaccount.yaml`) e recebe papel direto no
recurso que usa pelo identificador `principal://` da KSA, com o número do
projeto (`infra/terraform/modules/workload-identity/main.tf`):

| KSA | Papel | Recurso |
|---|---|---|
| `donation/donation-service` | `roles/pubsub.publisher` | tópico `donation-events` |
| `notification/notification-service` | `roles/pubsub.subscriber` | assinatura `notification-service` |
| `volunteer/volunteer-service`, `notification/notification-service` | `roles/datastore.user` | Firestore (projeto) |
| `velero/velero-server` | via GSA `solidarytech-velero`: `storage.objectAdmin` | bucket de DR |

GitHub Actions: Workload Identity Federation com um pool e um provider OIDC
(`infra/terraform/bootstrap/main.tf`). A condição do provider aceita só este
repositório, pelos IDs numéricos quando informados (um repositório recriado
com o mesmo nome não herda o acesso). Cada SA do CI fica presa a um tipo de
job pelo `subject`/`ref` do token:

| SA | Quem pode usar | O que pode fazer |
|---|---|---|
| `ci-deployer` | push na branch padrão | escrever no repositório do Artifact Registry |
| `ci-selfheal` | jobs da branch padrão (dispatch) | `roles/container.viewer` (dá o `container.clusters.connect` do endpoint DNS) e, no cluster, só reiniciar Deployments (RBAC) |
| `ci-terraform-plan` | `pull_request` | leitura (`viewer`, `iam.securityReviewer`, state só leitura) |
| `ci-terraform` | environment `production` | apply |

## Consequências

- Não há segredo de nuvem para vazar ou rotacionar no GitHub.
- O apply só roda num job com `environment: production`, que pode exigir
  aprovação (Settings > Environments).
- O self-heal usava `roles/container.clusterViewer` no primeiro desenho; a
  documentação do GKE lista só `container.viewer` e `container.developer`
  como papéis que dão acesso pelo endpoint DNS, então ficou o `viewer`, que
  é só leitura e não lê Secrets.
- Workload Identity em tempo de execução e a federação com o GitHub:
  validado na nuvem: pendente. Os bindings e as condições estão cobertos por
  `terraform test` (`modules/workload-identity/tests`, `bootstrap/tests`).
