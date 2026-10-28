# Visão geral da arquitetura no GCP

A SolidaryTech tem quatro microsserviços. Três são HTTP públicos (ONGs,
doações e voluntários) e um consome eventos de doação em segundo plano.

```
                      Internet (HTTPS, <ip>.sslip.io)
                                   │
              Load balancer global do Google (Gateway API)
              certificado do Certificate Manager, HTTP -> HTTPS
                                   │
        ┌──────────────┬───────────┴────────┬───────────────┬──────────────┐
    /ngos         /donations          /volunteers       /grafana      /sonarqube
        │              │                    │
  ngo-service   donation-service    volunteer-service
  (Python)      (Go)                (Python)
        │              │                    │
        │              │ publica evento     │
        ▼              ▼ (event_id)         ▼
   Cloud SQL      Pub/Sub ──────────►  Firestore
   ngo_db         donation-events      volunteers
   donation_db ◄──┘    │
                       │ assinatura notification-service (DLQ após 10)
                       ▼
               notification-service ──► Firestore donation_notifications
               (Python, consumidor)

   GKE Standard regional em southamerica-east1, nós privados, Workload Identity
```

## Componentes

| Componente | Onde está o código | Onde está a infraestrutura |
|---|---|---|
| ngo-service | `services/ngo-service` | Cloud SQL `ngo_db` (`infra/terraform/modules/data`) |
| donation-service | `services/donation-service` | Cloud SQL `donation_db`, tópico `donation-events` |
| volunteer-service | `services/volunteer-service` | Firestore, coleção `volunteers` |
| notification-service | `services/notification-service` | assinatura `notification-service`, coleção `donation_notifications` |
| Cluster | n/a | `infra/terraform/modules/gke` |
| Exposição | `deploy/gitops/addons/gateway`, `apps/*/overlays/prod/gateway.yaml` | `infra/terraform/modules/edge` |
| Entrega contínua | `deploy/gitops` (ArgoCD) | `infra/terraform/modules/platform` |
| Observabilidade | `deploy/gitops/addons/{otel-collector-*,kube-prometheus-stack,loki,grafana-dashboards}` | `infra/terraform/modules/observability` |
| Backup | `deploy/gitops/addons/velero` | bucket de DR em `modules/data`, GSA em `modules/workload-identity` |

## Caminho de uma doação

1. `POST /donations` chega ao Gateway e vai para o donation-service, que
   grava em `donation_db` (`services/donation-service/handlers.go`).
2. O donation-service publica o evento no Pub/Sub com os atributos
   `traceparent` e `event_id` e responde sem esperar a confirmação do
   Pub/Sub (`pubsub.go`).
3. O notification-service recebe por streaming pull, grava em
   `donation_notifications/<event_id>` e só então confirma (ack). Se a
   gravação falhar, a mensagem volta; depois de 10 entregas, vai para a DLQ.
4. O trace continua do HTTP ao consumidor pelo `traceparent`, e o OTel
   Collector manda os traces para o Datadog, de onde saem as métricas dos
   SLOs.

## Onde cada coisa é decidida

As decisões e os motivos estão nas ADRs em [adr/](adr/). Os detalhes de
rede e identidade estão em [rede-e-seguranca.md](rede-e-seguranca.md), os de
banco e mensageria em [dados-e-mensageria.md](dados-e-mensageria.md) e os
de entrada HTTPS em [exposicao-e-tls.md](exposicao-e-tls.md).
