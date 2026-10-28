# FinOps

## Rastreio de custo

Todo recurso do Terraform que aceita label recebe, pelo `default_labels` do
provider (`infra/terraform/envs/prod/infra/versions.tf`):

| Label no GCP | Valor | Tag da versão Azure |
|---|---|---|
| `project` | `solidarytech` | `Project = SolidaryTech` |
| `environment` | `production` | `Environment = Production` |
| `costcenter` | `ngo-core` | `CostCenter = NGO-Core` |
| `managed-by` | `terraform` | `ManagedBy = terraform` |
| `component` | `kubernetes`, `registry`, ... | `Component` |

As labels do GCP só aceitam minúsculas, números, `-` e `_`; por isso os
valores mudaram de forma, não de significado. As tags da versão Azure estão
em `fiap-tc-5-terraform/main.tf` na `main`.

No billing, o relatório filtrado por `project=solidarytech` e agrupado por
`costcenter` ou `component` é o equivalente do Cost Management por tags.
Dentro do cluster, o GKE cost allocation (`cost_management_config` em
`modules/gke/main.tf`) separa o custo por namespace e por label dos pods.

## Onde o custo foi contido

| Alavanca | Onde |
|---|---|
| Nós `e2-standard-2`, autoscaling de 1 a 2 por zona | `envs/prod/infra/variables.tf`, `modules/gke` |
| VPA em modo de recomendação (`updateMode: "Off"`, um por serviço; `kubectl -n <ns> describe vpa <serviço>`) e painel de rightsizing (uso de CPU contra request) | `modules/gke`, `deploy/gitops/apps/*/base/vpa.yaml`, `deploy/gitops/addons/grafana-dashboards` |
| Cloud Logging e Monitoring só dos componentes de sistema (o resto vai para Loki e Prometheus no cluster) | `modules/gke/main.tf` |
| Artifact Registry guarda as 20 versões mais recentes e apaga o resto depois de 30 dias | `envs/prod/infra/main.tf` |
| Bucket de DR passa para Nearline depois de 30 dias e apaga depois de 120 | `modules/data/main.tf` |
| DR sem cluster ligado (só a réplica do banco) | `envs/dr/infra`, [ADR 0009](../arquitetura/adr/0009-dr-pilot-light.md) |
| Orçamento mensal com alertas em 50%, 90% e 100% (opcional, padrão R$ 1.500) | `bootstrap/main.tf` |

## Riscos de custo e de cota

- O cluster regional tem pelo menos 3 nós (um por zona) e pode chegar a 6.
  Uma conta de avaliação costuma ter cota de vCPU menor que os 12 vCPU
  desse teto; nesse caso o autoscaling para antes do máximo. Confira em
  IAM e administrador > Cotas antes do primeiro deploy, ou reduza
  `max_nodes_per_zone`.
- Cloud SQL `REGIONAL` custa perto do dobro do zonal; é o preço do failover
  automático entre zonas. Para um ambiente de testes, `sql_tier` e a
  disponibilidade podem ser reduzidos por variável.
- O load balancer global cobra por regra de encaminhamento mesmo sem
  tráfego.

Não registrei valores em reais por recurso: preço muda por região, por
desconto da conta e com o tempo. A estimativa deve sair da calculadora do
Google com as quantidades acima, e o acompanhamento, do orçamento do
bootstrap.
