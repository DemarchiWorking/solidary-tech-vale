# SRE: SLIs, SLOs e resposta automática

Os SLOs estão como código em `infra/terraform/modules/observability/main.tf`,
com os valores padrão de `modules/observability/variables.tf`. Por padrão
cobrem o donation-service, o caminho de dinheiro e o SLO exigido no
desafio; os outros serviços entram pela variável `monitored_services` de
`envs/prod/observability` (a mesma escolha da versão Azure).

## SLIs e SLOs (janela de 30 dias)

| SLI | Medida | SLO | Aviso | Alerta |
|---|---|---|---|---|
| Disponibilidade | requisições sem 5xx / total (`trace.http.server.request.errors` e `.hits`) | 99,9% | 99,95% | monitor de 5xx acima de 5% em 5 min |
| Latência | p95 de `trace.http.server.request` | 99% do tempo com o monitor de p95 em OK (SLO do tipo monitor) | n/a | monitor de p95 acima de 0,5 s em 5 min |

Error budget de disponibilidade: 0,1% de 30 dias, perto de 43 minutos de
indisponibilidade total por mês, ou o equivalente em requisições com erro.
O painel `SolidaryTech - SRE (SLO & Error Budget)` mostra o consumo.

A latência é medida em segundos: o limite do monitor é
`latency_p95_threshold_seconds = 0.5`. Na versão Azure ele estava em
milissegundos contra uma métrica em segundos, o que nunca disparava.

## O que acontece quando um alerta dispara

| Gatilho | PagerDuty | Discord | Self-heal |
|---|---|---|---|
| 5xx acima de 5% | abre incidente | avisa | `rollout restart` do serviço |
| p95 acima do limite | abre incidente | avisa | não (reiniciar não resolve latência de dependência) |
| Watchdog (anomalia detectada pelo Datadog) | n/a | avisa | não |
| Mensagem parada na DLQ (Cloud Monitoring) | n/a | n/a | não; alguém precisa olhar a mensagem |

O self-heal está descrito em [ci-cd.md](../plataforma/ci-cd.md#self-heal).
Reiniciar é seguro porque os serviços são stateless, o PDB mantém pelo
menos uma réplica e o load balancer drena as conexões por 30 s antes de
tirar o pod.

## Confiabilidade embutida no deploy

- 2 réplicas no mínimo por serviço, espalhadas por zona (topology spread).
- PodDisruptionBudget `minAvailable: 1`.
- preStop de 10 s e 60 s de graça para terminar, e desligamento gracioso no
  donation-service (fecha o servidor HTTP e espera as publicações
  pendentes).
- readiness e liveness em `/health`; o notification-service responde 503 se
  o consumidor do Pub/Sub morrer, e o Kubernetes reinicia o pod.
- HPA no donation-service (2 a 10 réplicas, 70% de CPU).
- Cluster e Cloud SQL regionais (três zonas).

## Validação

Os monitores e SLOs passam no `terraform test` do módulo, com mocks. Os
alertas disparando de verdade e o ciclo Datadog, GitHub, GKE: validado na
nuvem: pendente.
