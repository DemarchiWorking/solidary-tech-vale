# Observabilidade

## Coleta

```
serviços (OTel SDK, OTLP HTTP)
      │
      ▼
otel-collector-gateway (Deployment, namespace monitoring)
      ├── traces  ──► Datadog         (exporter datadog; daí saem as métricas trace.http.server.request.*)
      ├── métricas ──► Prometheus      (remote write no kube-prometheus-stack)
      └── logs    ──► Loki

otel-collector-logs (DaemonSet) ──► Loki   (logs dos containers de cada nó)
```

Arquivos: `deploy/gitops/addons/otel-collector-gateway/values.yaml`,
`otel-collector-logs/values.yaml`, `kube-prometheus-stack/values.yaml`
(Prometheus com retenção de 30 dias, Grafana) e `loki/values.yaml`
(retenção de 72 h, 10 Gi).

Os serviços Go e Python usam os mesmos limites de histograma de duração
HTTP; no Python isso vem de `explicit_bucket_boundaries_advisory` em cada
`app.py`, para o SLO de latência ter resolução nas faixas que importam.

O donation-service propaga o contexto de trace na mensagem do Pub/Sub
(`traceparent`), e o notification-service continua o mesmo trace no
consumidor.

## Painéis

Os dashboards ficam em `deploy/gitops/addons/grafana-dashboards` como
ConfigMaps que o Grafana carrega sozinho:

- `SolidaryTech - Overview`: saúde do cluster GKE (CPU e memória por nó,
  restarts de pods) e rightsizing (uso de CPU contra o request, por
  Deployment);
- `SolidaryTech - SRE (SLO & Error Budget)`: taxa de erros e consumo do
  error budget na janela de 30 dias.

O Grafana fica em `https://<host>/grafana`, com o usuário e a senha do
Secret `grafana-admin` (gerados pelo Terraform):

```bash
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d
```

## Alertas, SLOs e incidentes

Estão em `infra/terraform/modules/observability` e descritos em
[sre-slo.md](../operacao/sre-slo.md) e
[itsm-aiops.md](../operacao/itsm-aiops.md). Além do Datadog, o Cloud
Monitoring tem um alerta nativo para mensagens paradas na DLQ
(`modules/data/main.tf`).

## Configuração

- A chave do Datadog chega ao collector pelo Secret `datadog-api-key`
  (namespace monitoring), criado pelo Terraform.
- O site do Datadog no collector é `datadoghq.com`. Se a conta for de outro
  site (us3, us5, eu), troque em `otel-collector-gateway/values.yaml` e em
  `datadog_site` da stack de observabilidade; com o site errado, o exporter
  falha na autenticação sem erro visível no serviço.
- Logs e métricas do próprio GKE no Cloud Logging e no Cloud Monitoring
  ficam só nos componentes de sistema (`SYSTEM_COMPONENTS` em
  `modules/gke/main.tf`), porque os dos serviços já vão para Loki e
  Prometheus; isso evita pagar duas vezes pela mesma linha de log.
