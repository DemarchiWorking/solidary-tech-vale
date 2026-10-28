# Runbook 05. Failover para southamerica-west1

Quando `southamerica-east1` está indisponível e não há previsão de volta
dentro do RTO. O desenho está na
[ADR 0009](../../arquitetura/adr/0009-dr-pilot-light.md) e os objetivos em
[pcn-dr.md](../pcn-dr.md). Este roteiro ainda não foi ensaiado: validado na
nuvem: pendente.

A ordem importa. A promoção da réplica do Cloud SQL é sem volta e, depois
dela, um `terraform apply` em `envs/dr/infra` tentaria recriar a instância
como réplica (o `master_instance_name` força troca). Por isso o cluster de
DR sobe antes, e a instância promovida sai do state antes de qualquer apply
novo.

## 0. Declarar o incidente

Registre no PagerDuty, avise o canal e congele os deploys (não faça merge
na `main` até o passo 7).

## 1. Subir o cluster de DR (10 a 15 min)

```bash
cd infra/terraform/envs/dr/infra && cp backend.hcl.example backend.hcl
```

```bash
terraform init -backend-config=backend.hcl && terraform apply -var cluster_enabled=true
```

Esta stack lê os outputs de produção do bucket do state, que fica em
`southamerica-east1`. Se ele não responder, ver "Se o state não responder"
no fim.

## 2. Promover a réplica do Cloud SQL

```bash
eval "$(terraform output -raw promote_replica_command)"
```

E tire a instância do controle desta stack:

```bash
terraform state rm 'google_sql_database_instance.replica[0]'
```

## 3. Firestore na região de DR

```bash
gcloud firestore databases create --database=dr --location=southamerica-west1 --project <id-do-projeto>
```

```bash
gsutil ls gs://<bucket-de-dr>/firestore/
```

```bash
gcloud firestore import gs://<bucket-de-dr>/firestore/<pasta-mais-recente> --database=dr --project <id-do-projeto>
```

No GitOps, acrescente `FIRESTORE_DATABASE` com valor `dr` no `env` de
`deploy/gitops/apps/volunteer/base/deployment.yaml` e
`deploy/gitops/apps/notification/base/deployment.yaml` (os serviços já leem
essa variável; o padrão é `(default)`). Commit e push na `main`.

## 4. Imagens num repositório da região de DR

O Artifact Registry de produção é regional.

```bash
gcloud artifacts repositories create solidarytech --repository-format=docker --location=southamerica-west1 --project <id-do-projeto>
```

Troque a variável `GCP_REGISTRY` do GitHub para
`southamerica-west1-docker.pkg.dev/<id-do-projeto>/solidarytech` e rode os
4 CIs (Run workflow); cada um publica a imagem no novo repositório e grava a
tag no GitOps. A SA `ci-deployer` precisa de escrita nele:

```bash
gcloud artifacts repositories add-iam-policy-binding solidarytech --location=southamerica-west1 --member="serviceAccount:<ci-deployer>" --role=roles/artifactregistry.writer --project <id-do-projeto>
```

E os nós do cluster de DR, de leitura:

```bash
gcloud artifacts repositories add-iam-policy-binding solidarytech --location=southamerica-west1 --member="serviceAccount:<sa-dos-nos-do-dr>" --role=roles/artifactregistry.reader --project <id-do-projeto>
```

## 5. Liberar o IP do Gateway

O IP global e o certificado continuam válidos, mas o load balancer do
cluster antigo ainda segura o IP. Liste e apague as regras que apontam para
ele:

```bash
gcloud compute forwarding-rules list --global --filter="IPAddress=<ip-do-gateway>" --project <id-do-projeto>
```

```bash
gcloud compute forwarding-rules delete <regra> --global --project <id-do-projeto>
```

## 6. Plataforma no cluster de DR

```bash
cd infra/terraform/envs/dr/platform && cp backend.hcl.example backend.hcl
```

```bash
terraform init -backend-config=backend.hcl && terraform apply -var state_bucket=<bucket-do-state> -var datadog_api_key=<chave> -var argocd_github_token=<token> -var selfheal_service_account=<ci-selfheal>
```

A stack cria os Secrets com as URLs do banco apontando para o IP da réplica
promovida e instala o ArgoCD, que aplica o mesmo GitOps. Workload Identity
funciona sem mudança: o pool é do projeto, então as mesmas KSAs têm os
mesmos papéis no cluster novo.

Atualize no GitHub `GKE_CLUSTER_NAME=solidarytech-dr` e
`GKE_LOCATION=southamerica-west1`, para o self-heal agir no cluster novo.

## 7. Conferir

Os mesmos testes do passo 6 do
[runbook 02](02-primeiro-deploy.md#6-conferir-de-fora), com o host de
sempre. Confira também uma doação chegando ao Firestore `dr`.

## Voltar para southamerica-east1

Com a região de volta: recriar a produção pela stack `envs/prod/infra` com
o Cloud SQL como réplica da instância de DR, deixar replicar, repetir este
roteiro no sentido contrário e, por fim, voltar `FIRESTORE_DATABASE`,
`GCP_REGISTRY` e as variáveis do GKE. Planeje numa janela de manutenção.

## Se o state não responder

O bucket do state é regional (`location = var.region` em
`bootstrap/main.tf`). Numa perda total da região, os comandos `terraform`
deste roteiro não leem os outputs de produção. Para não depender disso,
copie o state para a raiz do bucket de DR depois de cada apply de
produção; os prefixos (`prod/infra`, `dr/infra`, ...) não colidem com
`velero/` e `firestore/`:

```bash
gsutil -m rsync -r gs://<id-do-projeto>-tfstate gs://<bucket-de-dr>
```

No incidente, use `-backend-config="bucket=<bucket-de-dr>"` no `init` e
`-var state_bucket=<bucket-de-dr>` nas stacks de DR. O ciclo de vida do
bucket de DR apaga objetos com mais de 120 dias, então a cópia precisa ser
refeita com frequência. Esse espelhamento ainda não é automático.
