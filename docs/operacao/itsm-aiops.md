# ITSM e AIOps

O fluxo de incidente está em `infra/terraform/modules/observability/main.tf`
e é aplicado pela stack `envs/prod/observability`.

```
Datadog
  ├── monitor de 5xx      ──► @pagerduty-<serviço>   ──► incidente, escalonamento
  │                       ──► @webhook-discord-alerts ──► canal do time
  │                       ──► @webhook-github-selfheal-<serviço> ──► rollout restart no GKE
  ├── monitor de p95      ──► PagerDuty e Discord
  └── Watchdog (anomalia) ──► Discord
```

## PagerDuty (ITSM)

- Um serviço `solidarytech-<serviço>` por serviço monitorado, integrado ao
  Datadog (`datadog_integration_pagerduty_service_object`).
- Política de escalonamento `SolidaryTech - On-call`: aciona o usuário dono
  (variável `pagerduty_user_email`) e, sem reconhecimento, aciona de novo a
  cada 10 minutos, por dois ciclos (`num_loops = 2`).
- O incidente leva o texto do monitor: o que passou do limite, o SLO
  afetado e, no caso de 5xx, a ação automática que o self-heal vai tomar.

## ChatOps

Um webhook `discord-alerts` usa o formato do Slack (`/slack` no fim da URL
do Discord) e manda título, mensagem, transição, prioridade e o link do
evento no Datadog.

## AIOps

- O monitor `[SolidaryTech] Watchdog detectou anomalia` alerta quando o
  Watchdog do Datadog registra um evento de anomalia para um serviço
  monitorado em produção nos últimos 30 minutos. É o aviso que chega antes
  de um limiar fixo.
- O self-heal fecha o ciclo sem gente para o caso mais comum (erro 5xx por
  estado ruim do processo): o alerta vira `repository_dispatch`, que vira
  `kubectl rollout restart`, e o resultado (pods depois do restart) fica no
  log do workflow como evidência. O incidente no PagerDuty continua aberto
  para alguém confirmar a causa.

## Fluxo de um incidente

1. O monitor dispara e o PagerDuty abre o incidente.
2. Se for 5xx, o self-heal reinicia o serviço; o workflow
   `<serviço>-self-heal.yml` mostra o antes e o depois.
3. O on-call reconhece, olha o painel de SRE no Grafana e os traces no
   Datadog e decide entre esperar o monitor normalizar, fazer rollback
   ([runbook 03](runbooks/03-rollback.md)) ou restaurar dados
   ([runbook 04](runbooks/04-restore-velero.md)).
4. Quando o monitor volta a OK, o PagerDuty resolve o incidente.

## Validação

O módulo passa no `terraform test` com mocks dos providers Datadog e
PagerDuty. A criação real dos serviços e webhooks e um incidente de verdade
passando por PagerDuty, Discord e self-heal: validado na nuvem: pendente.
