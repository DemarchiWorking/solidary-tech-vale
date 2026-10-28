# Continuidade de negócio e recuperação de desastre

O desenho é "pilot light" em `southamerica-west1`
([ADR 0009](../arquitetura/adr/0009-dr-pilot-light.md)): os dados ficam
copiados na outra região o tempo todo e a computação só sobe no failover.

## Proteção por componente

| Componente | Falha de zona | Falha lógica (dado apagado ou corrompido) | Perda da região |
|---|---|---|---|
| GKE e serviços | cluster regional, 2 réplicas por serviço espalhadas por zona | rollback pelo Git ([runbook 03](runbooks/03-rollback.md)) | cluster de DR + mesmo GitOps |
| Cloud SQL | HA regional, failover automático | PITR de 7 dias (restaura para um minuto específico) | réplica em `southamerica-west1`, promovida no failover |
| Pub/Sub | serviço regional/global gerenciado | retenção de 7 dias no tópico e na assinatura, DLQ | serviço global; os serviços do DR publicam e consomem no mesmo tópico |
| Firestore | serviço regional gerenciado | PITR e backup diário (7 dias) | export diário para o bucket de DR, importado num banco novo |
| Objetos do cluster | n/a | Velero: diário dos 4 namespaces dos serviços (30 dias) e de hora em hora do donation (7 dias); o Git tem o resto | restore do Velero no cluster de DR, ou o próprio GitOps |
| Imagens | Artifact Registry regional | tags imutáveis | rebuild pelo CI a partir do Git |

Fontes: `modules/data/main.tf` (Cloud SQL, Pub/Sub, Firestore, bucket),
`envs/dr/infra/main.tf` (réplica e cluster de DR),
`deploy/gitops/addons/velero/schedule.yaml` (agendas).

## Objetivos

| Cenário | RPO | RTO | Como |
|---|---|---|---|
| Perda de uma zona | 0 | minutos, automático | HA do Cloud SQL, nós e pods em outras zonas |
| Deploy ruim | 0 | minutos | rollback pelo ArgoCD ou `git revert` |
| Dado apagado no PostgreSQL | até 5 min | menos de 1 h | PITR para uma instância nova e cópia dos dados |
| Namespace apagado | até 1 h (donation) ou 24 h (demais) | até 30 min (donation) | restore do Velero ([runbook 04](runbooks/04-restore-velero.md)) |
| Perda da região de produção | segundos (PostgreSQL), até 24 h (Firestore) | cerca de 1 h a 2 h | [runbook 05](runbooks/05-failover-regiao-dr.md) |

Os RPOs vêm da configuração (replicação contínua, PITR, frequência dos
backups e do export). Os RTOs são estimativas a partir dos passos do
runbook (o que mais pesa é criar o cluster de DR e esperar o certificado do
Gateway) e só passam a ser medida depois de um ensaio: validado na nuvem:
pendente.

## Limites conhecidos

- O Firestore não tem réplica entre regiões neste desenho; o que foi
  gravado depois do último export diário se perde numa perda total da
  região. Os voluntários podem ser recadastrados e as notificações podem
  ser regeradas reprocessando as doações do PostgreSQL.
- O IP do Gateway e o certificado são globais e o host sslip.io é derivado
  do IP, então o cluster de DR reutiliza os dois. Antes, as regras de
  encaminhamento do load balancer antigo precisam ser apagadas para liberar
  o IP (runbook 05, passo 5).
- A promoção da réplica do Cloud SQL é sem volta: depois do failover, a
  produção antiga precisa ser recriada como réplica da nova.
- O Artifact Registry e o bucket do state do Terraform são regionais, em
  `southamerica-east1`. No failover, as imagens são republicadas pelo CI num
  repositório criado na região de DR, e o state precisa de uma cópia no
  bucket de DR feita antes do incidente (runbook 05).
- O Firestore de produção é o banco `(default)` em `southamerica-east1`.
  No failover, o export é importado num banco `dr` em `southamerica-west1`
  e os serviços passam a usar `FIRESTORE_DATABASE=dr`.

## Ensaios recomendados

| Ensaio | Frequência | Runbook |
|---|---|---|
| Restore do Velero de um namespace num cluster de teste | trimestral | 04 |
| PITR do Cloud SQL para uma instância temporária | trimestral | 04 (seção do banco) |
| Failover completo para `southamerica-west1` | anual | 05 |
