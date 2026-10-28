# Rede e segurança

## Rede

Uma VPC (`solidarytech-vpc`) com uma sub-rede por região, criada em
`infra/terraform/modules/network` e configurada em
`infra/terraform/envs/prod/infra/main.tf`:

| Sub-rede | Região | Nós | Pods | Services |
|---|---|---|---|---|
| `prod` | southamerica-east1 | 10.10.0.0/20 | 10.16.0.0/14 | 10.20.0.0/20 |
| `dr` | southamerica-west1 | 10.30.0.0/20 | 10.32.0.0/14 | 10.36.0.0/20 |

- Private Service Access em 10.40.0.0/16: é por onde o Cloud SQL ganha IP
  privado dentro da VPC.
- Cloud NAT em cada região, para os nós privados saírem para a internet
  (imagens públicas, Datadog, GitHub) sem IP público.
- Private Google Access ligado nas sub-redes: APIs do Google sem sair pela
  internet.
- A sub-rede `dr` existe desde o início, sem tráfego, para a réplica do
  Cloud SQL e o cluster de contingência ficarem na mesma VPC.

## Cluster

Em `infra/terraform/modules/gke/main.tf`:

- nós privados e endpoint privado (`enable_private_nodes`,
  `enable_private_endpoint`): nenhum nó nem o IP do control plane ficam na
  internet;
- acesso administrativo pelo endpoint DNS do control plane
  (`dns_endpoint_config.allow_external_traffic`), autenticado e autorizado
  pelo IAM do Google em cada chamada; quem não tem
  `container.clusters.connect` não chega à API do Kubernetes;
- redes autorizadas no endpoint por IP limitadas à faixa dos nós
  (`master_authorized_cidrs = { nos-prod = "10.10.0.0/20" }`);
- Workload Identity (`GKE_METADATA` nos nós), Shielded Nodes com secure boot
  e integrity monitoring, SA de nó dedicada com
  `roles/container.defaultNodeServiceAccount` (logs e métricas) e leitura só
  do repositório de imagens (`envs/prod/infra/main.tf`);
- Dataplane V2, que aplica NetworkPolicy quando houver.

## Identidade

Nenhuma chave de service account existe. Os pods usam Workload Identity e o
GitHub Actions usa Workload Identity Federation; as tabelas de quem pode o
quê estão na [ADR 0007](adr/0007-identidade-sem-chave.md).

O self-heal entra pelo endpoint DNS com `roles/container.viewer` no IAM
(leitura, sem Secrets) e, dentro do cluster, só pode `get`, `list`, `watch`
e `patch` em Deployments e ler ReplicaSets e Pods nos 4 namespaces dos
serviços (Role `selfheal-rollout-restart` em `modules/platform/main.tf`).

## Segredos

Nenhum segredo está no Git. O Terraform cria todos os Secrets do cluster
(`modules/platform/main.tf`), e o GitOps só referencia os nomes:

| Secret | Namespace | Conteúdo | Origem |
|---|---|---|---|
| `db-secrets` | ngo, donation | URL do banco com usuário próprio | senha gerada em `modules/data` |
| `datadog-api-key` | monitoring | chave do Datadog | secret `DD_API_KEY` do GitHub ou tfvars |
| `grafana-admin` | monitoring | usuário e senha do Grafana | `random_password` |
| `sonarqube-jdbc`, `sonarqube-admin`, `sonarqube-monitoring` | sonarqube | senha do banco, do admin e passcode | `random_password` |

O ConfigMap `gcp-config` (donation, volunteer, notification) leva só o ID do
projeto.

## Banco

Cloud SQL só com IP privado (`ipv4_enabled = false`) e
`ssl_mode = "ENCRYPTED_ONLY"`, e as URLs dos serviços usam
`sslmode=require`. Cada serviço tem o seu usuário (`ngo_app`,
`donation_app`, mais `sonarqube`). Os usuários criados pela API do Cloud SQL
entram no papel `cloudsqlsuperuser`; para isolar um serviço do banco do
outro, o passo seguinte é revogar `CONNECT` no banco alheio com `REVOKE`
dentro do PostgreSQL (ver [dados-e-mensageria.md](dados-e-mensageria.md)).

## Cadeia de entrega

- Toda action dos workflows é fixada por SHA de commit; o
  `scripts/ci/checar_workflows.py` falha se alguma não for.
- Trivy no código (`fs`) e na imagem, bloqueando CRITICAL, em todo build; e
  Trivy `config` no Terraform, bloqueando HIGH e CRITICAL.
- Imagens com usuário sem privilégios (uid 10001) e bases enxutas
  (`alpine:3.24` no Go, `python:3.12-slim` no Python).
- Pods com `securityContext` restrito: `runAsNonRoot`, seccomp
  `RuntimeDefault`, sem escalada de privilégio e sem nenhuma capability
  (`deploy/gitops/apps/*/base/deployment.yaml`). O `docker-compose.yml` roda
  os serviços com as mesmas restrições, então o E2E local prova que as
  imagens funcionam assim.
- Tags de imagem imutáveis no Artifact Registry: o SHA que o GitOps aponta
  nunca muda de conteúdo.
- O ArgoCD não tem IP público (ClusterIP); o acesso é por
  `kubectl port-forward` passando pelo endpoint DNS.

## O que ainda não existe

- NetworkPolicy. O Dataplane V2 aplicaria, mas as regras precisam liberar as
  faixas do load balancer e dos health checks do Google, o Prometheus e o
  OTel Collector; escrever isso sem um cluster para testar arriscaria cortar
  tráfego legítimo. Fica como próximo passo, testado no cluster.
- Isolamento de privilégios entre os usuários do Cloud SQL (`REVOKE`), pelo
  mesmo motivo.
