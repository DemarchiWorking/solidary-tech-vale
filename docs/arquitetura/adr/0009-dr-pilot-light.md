# ADR 0009. DR "pilot light" em southamerica-west1

Status: aceita (branch-gcp)

## Contexto

Um DR com cluster ligado o tempo todo dobra o custo de computação. Os dados
são o que não se recria; os serviços são stateless e o GitOps reconstrói o
cluster.

## Decisão

Sempre ligado, com custo baixo:

- réplica do Cloud SQL em `southamerica-west1`, na mesma VPC
  (`envs/dr/infra/main.tf`, `sql_replica_enabled`, padrão ligado);
- sub-rede `dr` e Cloud NAT já criados pela stack de produção;
- bucket de DR em `southamerica-west1` (`modules/data`), com os backups do
  Velero e o export diário do Firestore;
- backups do Cloud SQL guardados em `southamerica-west1`.

Ligado só no failover: o GKE de contingência
(`terraform apply -var cluster_enabled=true` em `envs/dr/infra`) e depois
`envs/dr/platform`, que instala o ArgoCD, que aplica o mesmo GitOps.

## Consequências

- RPO de segundos para o PostgreSQL (replicação contínua) e de até 24 h para
  o Firestore (export diário).
- RTO dominado pela criação do cluster de DR, pela republicação das imagens
  num repositório da região de DR (o Artifact Registry é regional) e pelo
  primeiro sync do ArgoCD. O passo a passo está no
  [runbook 05](../../operacao/runbooks/05-failover-regiao-dr.md), e a
  estimativa, em [pcn-dr.md](../../operacao/pcn-dr.md).
- Failover real (promoção da réplica, cluster de DR, restore do Firestore):
  validado na nuvem: pendente.
