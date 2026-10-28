# CI/CD

Onze workflows em `.github/workflows`. Toda action é fixada por SHA de
commit, e nenhum workflow guarda chave de nuvem: o acesso ao GCP é por
Workload Identity Federation ([ADR 0007](../arquitetura/adr/0007-identidade-sem-chave.md)).

## Workflows

| Workflow | Quando roda | O que faz |
|---|---|---|
| `<serviço>-ci.yaml` (4) | push e PR em `main`/`branch-gcp` que mexem em `services/<serviço>/**` | lint, testes, SonarQube (se configurado), Trivy no código e na imagem; na branch padrão, publica a imagem e atualiza o GitOps |
| `<serviço>-self-heal.yml` (4) | `repository_dispatch` `self-heal-<serviço>` (webhook do Datadog) ou manual | `kubectl rollout restart` do serviço no GKE |
| `terraform.yaml` | push e PR que mexem em `infra/terraform/**` | gate sem nuvem; plan no PR; apply na branch padrão |
| `gitops-validate.yaml` | push e PR que mexem em `deploy/gitops/**`, `scripts/**`, nos workflows ou na documentação | gate do GitOps, actionlint, checagens dos workflows e da documentação |
| `local-e2e.yaml` | push e PR que mexem nos serviços, no compose ou nos scripts locais | `docker compose up --wait`, smoke e `down -v` |

## CI de um serviço

```
lint ─┐
      ├─► sonarqube (pula sem SONAR_TOKEN)
test ─┤
      └─► build-scan-push ──► update-gitops
           Trivy fs, build,      kustomize edit set image,
           Trivy imagem,         commit com GITHUB_TOKEN,
           [auth WIF, login,     até 10 tentativas com rebase
            push :<sha>]
```

- Go: `go mod tidy` sem diff, `go vet`, golangci-lint v2.15, `go test -race`
  com cobertura. Go 1.26 (exigido pelo `pubsub/v2` v2.8.0).
- Python: flake8 e pytest com cobertura, em Python 3.12 (o mesmo das
  imagens).
- A publicação só acontece na branch padrão, fora de PR, e com as três
  variáveis `GCP_REGISTRY`, `GCP_WIF_PROVIDER` e `GCP_CI_SA`. Sem elas, a
  imagem é construída e escaneada e o job registra um aviso; nada falha.
- Só a tag do commit é publicada: o repositório tem tags imutáveis, então um
  `:latest` reaproveitado seria recusado.
- O `update-gitops` só roda se a imagem daquela execução foi publicada
  (output `publicado` do job anterior).

### Corrida entre serviços

Um push que mexe nos 4 serviços publica os 4 quase ao mesmo tempo, e os
quatro `update-gitops` disputam a branch. A primeira versão (3 tentativas,
5 s fixos) perdeu uma atualização numa simulação com 4 pushes simultâneos.
A versão atual tenta até 10 vezes com espera aleatória de 2 a 9 s; a mesma
simulação, repetida três vezes, terminou sempre com as 4 tags na branch.
Um grupo de `concurrency` comum aos 4 não resolveria: o GitHub cancela o
job pendente quando chega outro para o mesmo grupo.

## Self-heal

1. O monitor de taxa de 5xx do Datadog chama o webhook
   `github-selfheal-<serviço>` (`infra/terraform/modules/observability`), que
   faz `POST /repos/<owner>/<repo>/dispatches` com `event_type`
   `self-heal-<serviço>`.
2. O workflow confere as variáveis, troca o token OIDC pela SA
   `ci-selfheal`, pega credencial do GKE pelo endpoint DNS
   (`get-gke-credentials` com `use_dns_based_endpoint`) e roda
   `rollout restart` e `rollout status`.
3. O título do alerta, que vem de fora, entra só como variável de ambiente;
   a checagem `scripts/ci/checar_workflows.py` falha se algum `run:`
   interpolar `client_payload` direto.

O `repository_dispatch` só dispara workflows da branch padrão, então o
self-heal só funciona depois que a `branch-gcp` for para a `main`.

## Terraform

| Job | Quando | Identidade | O que faz |
|---|---|---|---|
| `static` | sempre | nenhuma | `scripts/ci/terraform-check.sh` (fmt, validate, test, tflint, Trivy) |
| `plan` | PR do próprio repositório, com as variáveis | `ci-terraform-plan` (leitura) | `plan -lock=false -refresh=false` de `envs/prod/infra` |
| `apply` | branch padrão, environment `production` | `ci-terraform` | plan e apply de infra, platform e observability, em ordem |

O plan do PR não faz refresh porque a SA de leitura não escreve lock no
state nem tem permissão de leitura detalhada de todo recurso; ele mostra o
efeito do código. O drift aparece no plan do apply, que faz refresh. Sem os
secrets do Datadog e do PagerDuty, a stack de observabilidade fica de fora
com um aviso; sem `DD_API_KEY`, a de platform falha com mensagem clara.

## Variáveis e secrets do repositório

Settings > Secrets and variables > Actions. Os valores saem dos outputs do
Terraform.

| Nome | Tipo | Valor | Usado por |
|---|---|---|---|
| `GCP_PROJECT_ID` | variável | ID do projeto | self-heal, terraform |
| `GCP_WIF_PROVIDER` | variável | output `workload_identity_provider` do bootstrap | todos que acessam o GCP |
| `GCP_CI_SA` | variável | output `ci_deployer_service_account` | CIs, terraform |
| `GCP_SELFHEAL_SA` | variável | output `ci_selfheal_service_account` | self-heals, terraform |
| `GCP_TF_PLAN_SA` | variável | output `ci_terraform_plan_service_account` | terraform (plan) |
| `GCP_TF_APPLY_SA` | variável | output `ci_terraform_service_account` | terraform (apply) |
| `TF_STATE_BUCKET` | variável | output `state_bucket` | terraform |
| `GCP_REGISTRY` | variável | output `registry_url` de `envs/prod/infra` | CIs |
| `GKE_CLUSTER_NAME` | variável | output `cluster_name` | self-heals |
| `GKE_LOCATION` | variável | output `cluster_location` (padrão `southamerica-east1`) | self-heals |
| `SONAR_ORGANIZATION` | variável | chave da organização no SonarQube Cloud; vazia com SonarQube próprio ([runbook 06](../operacao/runbooks/06-sonarqube-no-ci.md#alternativa-sonarqube-cloud-sonarcloudio)) | CIs |
| `PAGERDUTY_USER_EMAIL`, `DD_SITE` | variáveis | e-mail do usuário do PagerDuty; site do Datadog (opcional) | terraform |
| `SONAR_TOKEN`, `SONAR_HOST_URL` | secrets | Global Analysis Token e `https://<host>/sonarqube` ([runbook 06](../operacao/runbooks/06-sonarqube-no-ci.md)); sem os dois, a análise é pulada com aviso | CIs |
| `DD_API_KEY`, `DD_APP_KEY` | secrets | chaves do Datadog | terraform |
| `PAGERDUTY_TOKEN`, `DISCORD_WEBHOOK_URL` | secrets | token do PagerDuty, webhook do Discord | terraform |
| `GH_SELFHEAL_TOKEN` | secret | token fine-grained deste repositório com Contents: Read and write | terraform (webhook do Datadog) |
| `ARGOCD_GITHUB_TOKEN` | secret | token fine-grained com Contents: Read (repositório privado) | terraform (platform) |

## Validação

- actionlint 1.7.12: 0 problemas nos 11 workflows.
- `scripts/ci/checar_workflows.py`: 0 falhas, e pega os quatro defeitos
  plantados num teste negativo (action sem SHA, payload interpolado, job sem
  `id-token: write`, caminho inexistente). Também falha num `run:` que roda
  antes do checkout dentro de uma pasta do repositório: foi o que quebrou o
  job do SonarQube na primeira execução no GitHub, quando os secrets ainda
  não existiam.
- Os comandos de cada job rodaram localmente: Go em `golang:1.26` com
  `-race`, Python em `python:3.12-slim`, os dois gates e o E2E com
  `docker compose`.
- A troca de token com o GCP, o push no Artifact Registry e o apply real:
  validado na nuvem: pendente.
