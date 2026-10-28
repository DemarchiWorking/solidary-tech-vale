# Runbook 02. Primeiro deploy em produção

Do projeto com bootstrap (runbook 01) aos quatro serviços respondendo em
HTTPS. Leva perto de 1 h 30: uns 25 min de Terraform (GKE e Cloud SQL), uns
10 min de ArgoCD e imagens, e até cerca de 1 h para o certificado sair.

## 0. A branch-gcp precisa ser a branch padrão

O ArgoCD lê `HEAD`, o CI só publica na branch padrão e o
`repository_dispatch` só roda workflows da branch padrão. Faça o merge da
`branch-gcp` na `main` (por PR, revisado) antes de seguir.

## 1. Infraestrutura (envs/prod/infra)

Pelo CI: o push na `main` que traz `infra/terraform/**` dispara o
`terraform.yaml`; o job `apply` espera a aprovação no environment
`production` e aplica infra, platform e observability, nessa ordem.

Ou localmente, para ver cada passo:

```bash
cd infra/terraform/envs/prod/infra && cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars
```

Preencha o bucket no `backend.hcl` e `project_id` e
`ci_deployer_service_account` no `terraform.tfvars`.

```bash
terraform init -backend-config=backend.hcl && terraform apply
```

Depois, cadastre no GitHub as variáveis que dependem deste passo:

| Variável | Output |
|---|---|
| `GCP_REGISTRY` | `registry_url` |
| `GKE_CLUSTER_NAME` | `cluster_name` |
| `GKE_LOCATION` | `cluster_location` |

## 2. Valores do ambiente no GitOps

Na raiz do repositório, com acesso ao state:

```bash
bash deploy/gitops/scripts/configurar-ambiente.sh infra/terraform/envs/prod/infra
```

O script grava o registry nas imagens, o host público no Grafana, o bucket
e a GSA no Velero e a URL do banco no SonarQube, e mostra o diff. Revise,
commite e faça push na `main`.

## 3. Plataforma (envs/prod/platform)

Se o passo 1 foi pelo CI, esta stack já foi aplicada. Localmente:

```bash
cd infra/terraform/envs/prod/platform && cp backend.hcl.example backend.hcl && cp terraform.tfvars.example terraform.tfvars
```

```bash
terraform init -backend-config=backend.hcl && terraform apply
```

Isso cria namespaces, Secrets, o ArgoCD e o app-of-apps. Acesso ao
cluster:

```bash
gcloud container clusters get-credentials solidarytech-prod --location southamerica-east1 --project <id-do-projeto> --dns-endpoint
```

```bash
kubectl -n argocd get applications
```

Se o `kubectl` responder `permission denied` pelo endpoint DNS, a sua conta
precisa de `roles/container.developer` ou `roles/container.admin` no
projeto.

## 4. Primeiras imagens

Rode cada CI pela aba Actions (Run workflow, branch `main`):
`donation-service-ci`, `ngo-service-ci`, `volunteer-service-ci`,
`notification-service-ci`. Cada um publica `<registry>/<serviço>:<sha>` e
faz o commit da tag no GitOps; o ArgoCD aplica.

```bash
kubectl get pods -A -l 'app in (donation-service,ngo-service,volunteer-service,notification-service)'
```

```bash
kubectl -n argocd get applications -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status
```

Os Jobs `db-init` rodam antes de cada sync de ngo e donation e criam as
tabelas.

## 5. Gateway e certificado

```bash
kubectl -n gateway get gateway solidarytech
```

```bash
gcloud certificate-manager certificates describe solidarytech-gateway --project <id-do-projeto> --format="value(managed.state)"
```

O Gateway fica `Programmed` em alguns minutos. O certificado passa de
`PROVISIONING` para `ACTIVE` em até cerca de 1 h; antes disso, o HTTPS não
responde, e o HTTP já redireciona.

## 6. Conferir de fora

```bash
HOST=$(terraform -chdir=infra/terraform/envs/prod/infra output -raw gateway_hostname)
```

```bash
curl -fsS -X POST "https://$HOST/ngos" -H "Content-Type: application/json" -d '{"name":"ONG Teste","email":"ong@example.org","cause":"Educacao","city":"Osasco"}'
```

```bash
curl -fsS -X POST "https://$HOST/donations" -H "Content-Type: application/json" -d '{"ngo_id":1,"amount":10.5,"donor_name":"Teste"}'
```

```bash
curl -fsS "https://$HOST/volunteers/1"
```

A notificação da doação aparece no Firestore, coleção
`donation_notifications` (console do Firestore), e o trace aparece no
Datadog com os spans do donation-service e do notification-service.

## 7. Depois do primeiro deploy

- Observabilidade: se os secrets do passo 6 do runbook 01 não estavam
  cadastrados, cadastre e rode o `terraform.yaml` de novo (Run workflow).
- Isolamento dos usuários do banco: rode os `REVOKE`/`GRANT` de
  [dados-e-mensageria.md](../../arquitetura/dados-e-mensageria.md#cloud-sql-postgresql-15).
- ArgoCD (sem IP público):

  ```bash
  kubectl -n argocd port-forward svc/argocd-server 8080:443
  ```

  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
  ```

Ao terminar, marque como feitos os itens de "validado na nuvem: pendente"
em [criterios-de-aceite.md](../../migracao/criterios-de-aceite.md).
