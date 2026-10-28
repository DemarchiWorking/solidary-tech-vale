# GitOps com ArgoCD

O cluster é descrito em `deploy/gitops` e aplicado pelo ArgoCD, que lê a
branch padrão do monorepo (`targetRevision: HEAD`). Ninguém roda
`kubectl apply` em produção.

## Como o ArgoCD chega ao cluster

O Terraform (`infra/terraform/modules/platform`) instala:

1. o ArgoCD (chart `argo-cd` 9.4.15), com o servidor em ClusterIP e o
   repositório cadastrado (com token de leitura, se o repositório for
   privado);
2. o app-of-apps `bootstrap` (chart `argocd-apps` 2.0.7), apontando para
   `deploy/gitops/applicationsets`, com sync automático e retry de 10
   tentativas (o primeiro sync chega antes das CRDs dos addons).

A partir daí:

```
bootstrap ──► deploy/gitops/applicationsets/
                ├── apps-appset.yaml   ApplicationSet: um app por pasta apps/*/overlays/prod
                └── addons.yaml        Application cluster-addons ──► deploy/gitops/addons/
                                         ├── gateway/                Gateway e redirect
                                         ├── kube-prometheus-stack/  Prometheus, Grafana (chart 90.0.0)
                                         ├── loki/                   logs (chart 7.3.0)
                                         ├── otel-collector-gateway/ traces e métricas (0.173.0)
                                         ├── otel-collector-logs/    DaemonSet de logs (0.173.0)
                                         ├── grafana-dashboards/     dashboards como ConfigMap
                                         ├── sonarqube/              (chart 2026.4.1)
                                         └── velero/                 backup (chart 12.1.0)
```

## Apps

O ApplicationSet gera `app-ngo`, `app-donation`, `app-volunteer` e
`app-notification`, cada um no namespace com o nome do app (segmento 3 do
caminho). Cada app tem:

| Arquivo | Conteúdo |
|---|---|
| `base/deployment.yaml` | Deployment com KSA, `securityContext` restrito, preStop de 10 s, `terminationGracePeriodSeconds: 60`, topology spread por zona, readiness e liveness em `/health`; 2 réplicas (donation sem `replicas`, ver HPA) |
| `base/service.yaml`, `serviceaccount.yaml`, `pdb.yaml` | Service, KSA (Workload Identity) e PodDisruptionBudget com `minAvailable: 1` |
| `base/vpa.yaml` | VerticalPodAutoscaler em `updateMode: "Off"`: só recomenda CPU e memória para ajustar os requests, sem reiniciar pod nem disputar com o HPA |
| `overlays/prod/kustomization.yaml` | imagem (`newName`/`newTag`, gravados pelo CI) |
| `overlays/prod/gateway.yaml` | HTTPRoute, HealthCheckPolicy, GCPBackendPolicy (ngo, donation, volunteer) |
| `overlays/prod/hpa.yaml` | só donation: HPA de 2 a 10 réplicas a 70% de CPU; o Deployment não fixa `replicas`, para o ArgoCD não brigar com o HPA |
| `overlays/prod/db-init-job.yaml`, `configmap.yaml` | Job `PreSync` que roda o `db/init.sql` (ngo, donation) |

## Como uma imagem nova chega ao cluster

1. O CI do serviço publica `<registry>/<serviço>:<sha>` no Artifact
   Registry.
2. O job `update-gitops` roda `kustomize edit set image` no overlay e faz
   commit com o `GITHUB_TOKEN` na branch padrão (o commit não dispara outros
   workflows).
3. O ArgoCD vê o commit e sincroniza o app. O rollout respeita o PDB, o
   preStop e o dreno de 30 s do load balancer.

Quando os 4 serviços publicam juntos, os commits disputam a branch. O job
tenta até 10 vezes com `git pull --rebase` e espera aleatória; uma
simulação com 4 pushes simultâneos contra um remoto local terminou com as 4
tags na branch nas três rodadas (ver [ci-cd.md](ci-cd.md)).

## Valores que só existem depois do Terraform

Registry, host público, bucket de DR, GSA do Velero e JDBC do SonarQube
saem dos outputs de `envs/prod/infra`. O script
`deploy/gitops/scripts/configurar-ambiente.sh <pasta envs/prod/infra>` lê
esses outputs e atualiza os arquivos pela chave; pode rodar de novo sem
estragar nada (a checagem roda o script duas vezes e compara). Enquanto ele
não roda, as imagens apontam para `registry-nao-configurado.invalid` e os
valores ficam como `__NOME__`, o que faz o script falhar se sobrar algum.

## Validação sem cluster

`bash scripts/ci/gitops-check.sh`:

- `kubectl kustomize` dos 4 apps, dos addons e dos dashboards;
- `helm template` de cada addon com o chart e a versão da Application e o
  `values.yaml` do repositório;
- `kubeconform -strict` em tudo, com os schemas das CRDs (Gateway API, GKE,
  ArgoCD, Velero, Prometheus Operator, snapshot) de um commit fixo do
  catálogo da Datree;
- `scripts/ci/checar_gitops.py`: KSA, `securityContext`, preStop, PDB,
  topology spread, `CLOUD_PROVIDER=gcp`, HTTPRoute no listener `https`,
  HealthCheckPolicy, hooks `PreSync`, retry em toda Application, repoURL do
  monorepo, segmento 3, nenhum Ingress e nenhum resto de Azure;
- o SQL de cada Job `db-init` duas vezes num PostgreSQL 15 com
  `ON_ERROR_STOP=1`, como o hook faz a cada sync (as tabelas usam
  `IF NOT EXISTS` e os dados iniciais, `ON CONFLICT DO NOTHING`);
- `configurar-ambiente.sh` duas vezes com um `terraform` falso;
- shellcheck dos scripts.

Roda no workflow `gitops-validate.yaml` e no `scripts/validar.sh`.
