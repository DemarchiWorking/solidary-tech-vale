# Runbook 04. Restore de backup (Velero e Cloud SQL)

## Velero (manifests e volumes do cluster)

O Velero roda no namespace `velero` com o plugin do GCP e Workload Identity
(KSA `velero-server`, GSA `solidarytech-velero`). Os backups vão para o
bucket de DR, prefixo `velero/`, e os volumes por snapshot CSI
(`VolumeSnapshotClass` do `pd.csi.storage.gke.io`).

| Agenda | Quando | O quê | Retenção |
|---|---|---|---|
| `solidarytech-daily` | 02:00 todo dia | ngo, donation, volunteer, notification e recursos do cluster | 30 dias |
| `solidarytech-donation-hourly` | de hora em hora | donation e recursos do cluster | 7 dias |

(`deploy/gitops/addons/velero/schedule.yaml`)

### Ver os backups

```bash
kubectl -n velero get backups.velero.io --sort-by=.metadata.creationTimestamp
```

Com a CLI do Velero instalada na sua máquina:

```bash
velero backup describe <backup> --details
```

### Restaurar um namespace

1. Tire o app do auto-sync do ArgoCD, senão ele recria os objetos enquanto
   o restore roda:

   ```bash
   kubectl -n argocd patch application app-<app> --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'
   ```

2. Apague o namespace danificado, se for o caso, e restaure:

   ```bash
   velero restore create --from-backup <backup> --include-namespaces <app>
   ```

   ```bash
   velero restore describe <restore> --details
   ```

3. Confira os pods e religue o auto-sync:

   ```bash
   kubectl -n <app> get pods
   ```

   ```bash
   kubectl -n argocd patch application app-<app> --type merge -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
   ```

Os serviços não guardam estado em volume (os dados estão no Cloud SQL e no
Firestore); o restore do Velero devolve configuração e objetos do
Kubernetes. As agendas pedem snapshot de volume, mas hoje os namespaces
incluídos não têm PVC, então nenhum snapshot é tirado. Os addons ficam de
fora de propósito: os dados do SonarQube estão no Cloud SQL (banco
`sonarqube`, coberto pelo backup e pelo PITR), e Prometheus e Loki guardam
telemetria de retenção curta, que o GitOps recria vazia. Se um app passar a
ter volume, o snapshot CSI já está configurado.

## Cloud SQL (PITR)

Para dado apagado ou corrompido no PostgreSQL. O PITR cria uma instância
nova no estado de um instante; a original continua intacta.

1. Escolha o instante, em UTC, antes do problema.
2. Clone:

   ```bash
   gcloud sql instances clone <instancia> <instancia>-pitr --point-in-time "2026-11-02T13:45:00Z" --project <id-do-projeto>
   ```

   O nome da instância está no output `sql_instance_name` de
   `envs/prod/infra`.

3. Copie de volta só o que se perdeu (por exemplo, com `pg_dump` da tabela
   na instância clonada e `psql` na original, a partir de um pod no
   cluster, que alcança o IP privado). Apague a instância clonada depois.

## Firestore

PITR de 7 dias e backup diário na própria região:

```bash
gcloud firestore backups list --location=southamerica-east1 --project <id-do-projeto>
```

```bash
gcloud firestore databases restore --source-backup=<nome-do-backup> --destination-database=restaurado --project <id-do-projeto>
```

O restore cria um banco novo (`restaurado`); para usar, aponte
`FIRESTORE_DATABASE` dos serviços para ele ou copie os documentos de volta.
O export diário em `gs://<bucket-de-dr>/firestore` serve para restaurar em
outra região (runbook 05).

## Validação

Agendas e configuração do Velero passam no `kubeconform` com os schemas das
CRDs e no `helm template` do chart 12.1.0. Um restore real: validado na
nuvem: pendente; o ensaio trimestral está em
[pcn-dr.md](../pcn-dr.md#ensaios-recomendados).
