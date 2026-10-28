# ADR 0001. GCP com GKE Standard regional em São Paulo

Status: aceita (branch-gcp)

## Contexto

A versão da `main` roda em AKS. A nova versão precisa rodar no Google Cloud
com o mesmo desenho de microsserviços, perto dos usuários (ONGs e doadores
no Brasil) e com alta disponibilidade, sem depender de uma zona só.

## Decisão

- Região de produção `southamerica-east1` (São Paulo) e região de DR
  `southamerica-west1` (Santiago), em `infra/terraform/envs/prod/infra/variables.tf`.
- GKE Standard regional (control plane replicado nas três zonas), com nós
  em `southamerica-east1-a`, `-b` e `-c`
  (`infra/terraform/modules/gke/main.tf`, variável `node_locations`).
- Pool `e2-standard-2` com autoscaling de 1 a 2 nós por zona
  (`location_policy = "BALANCED"`), disco `pd-balanced` e SA de nó dedicada.
- Canal de release `REGULAR`, Dataplane V2 (`ADVANCED_DATAPATH`), Gateway
  API, VPA e cost allocation habilitados no próprio cluster.

Escolhi Standard em vez de Autopilot pelo controle do tipo e da quantidade
de nós: numa conta com cota de vCPU limitada, o custo e o teto do cluster
ficam previsíveis, e os addons da plataforma (ArgoCD, Prometheus, Loki,
SonarQube e o coletor de logs em DaemonSet, em `deploy/gitops/addons`) rodam
nos mesmos nós que os serviços.

## Consequências

- Mínimo de 3 nós (um por zona). Com o máximo de 2 por zona, o cluster chega
  a 6 nós `e2-standard-2` (12 vCPU); uma conta de avaliação com cota menor
  trava o autoscaling antes disso (risco registrado em
  [finops.md](../../operacao/finops.md)).
- O control plane regional tem SLA maior que o zonal e não para em upgrade.
- A troca de região é uma variável; a de tipo de máquina também.
