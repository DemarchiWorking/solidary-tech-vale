# Exposição e TLS

A entrada HTTP é um Gateway só, do tipo load balancer global de aplicação
do Google (`gke-l7-global-external-managed`). A decisão e as alternativas
estão na [ADR 0006](adr/0006-gateway-api-certificate-manager-sslip.md).

## Peças

| Peça | Onde | O que faz |
|---|---|---|
| IP global `solidarytech-gateway-ip` | `infra/terraform/modules/edge` | endereço fixo do load balancer |
| Host `<ip-com-hifens>.sslip.io` | `modules/edge` (output `gateway_hostname`) | nome que resolve para o IP sem DNS próprio |
| Certificado e certmap `solidarytech-gateway-certmap` | `modules/edge` | certificado gerenciado do Certificate Manager para o host |
| Gateway `gateway/solidarytech` | `deploy/gitops/addons/gateway/manifests/gateway.yaml` | listeners `https` (443, certmap) e `http` (80) |
| Redirect | `addons/gateway/manifests/http-redirect.yaml` | HTTP para HTTPS com 301 |
| HTTPRoutes | `apps/{donation,ngo,volunteer}/overlays/prod/gateway.yaml`, `addons/kube-prometheus-stack/grafana-route.yaml`, `addons/sonarqube/route.yaml` | uma rota por prefixo, no namespace do serviço |
| HealthCheckPolicy | junto de cada rota | health check do load balancer: `/health` nos serviços (intervalo 10 s), `/grafana/api/health` e `/sonarqube/api/system/status` nos addons |
| GCPBackendPolicy | junto de cada rota dos serviços | dreno de conexões de 30 s, para rollout e self-heal não darem 502 |

## Rotas

| Prefixo | Serviço | Porta |
|---|---|---|
| `/ngos` | ngo-service | 8081 |
| `/donations` | donation-service | 8082 |
| `/volunteers` | volunteer-service | 8083 |
| `/grafana` | Grafana (kube-prometheus-stack) | 80 |
| `/sonarqube` | SonarQube (`sonarWebContext: /sonarqube`) | 9000 |

O caminho chega inteiro ao serviço, sem rewrite: os serviços registram as
rotas já com o prefixo, o Grafana usa `serve_from_sub_path` e o SonarQube
usa o web context. O listener `https` só aceita rotas de namespaces com a
label `solidarytech.io/gateway=true`, que o Terraform põe em ngo, donation,
volunteer, monitoring e sonarqube (`modules/platform/main.tf`); o listener
`http` só aceita o redirect do próprio namespace `gateway`.

## Certificado

O certificado usa autorização por load balancer: não há registro DNS a
criar, mas o Google só emite depois que o Gateway estiver servindo neste IP
com o certmap. A documentação do GKE exige que o listener HTTPS não tenha o
bloco `tls` quando o certificado vem por certmap, e é assim que está (a
checagem `scripts/ci/checar_gitops.py` falha se aparecer `tls`).

Ordem na primeira subida (runbook 02): o Terraform cria IP, certificado e
certmap; o ArgoCD cria o Gateway; o load balancer fica pronto em alguns
minutos; o certificado sai em até cerca de 1 hora. Até lá, o HTTPS não
responde.

Para usar domínio próprio, preencha `hostname` no `terraform.tfvars` de
`envs/prod/infra` (copiado do `.example`), aponte o registro A para o IP
(`terraform output gateway_hostname` mostra o host em uso) e rode o
`deploy/gitops/scripts/configurar-ambiente.sh` de novo, que atualiza o
domínio do Grafana.

## Validação

- Localmente: os manifests do Gateway, das rotas e das políticas passam no
  `kubeconform` estrito com os schemas das CRDs do Gateway API e do GKE, e
  as checagens estruturais conferem listener, certmap, IP nomeado e
  `HealthCheckPolicy` por Service (`scripts/ci/gitops-check.sh`).
- Na nuvem (provisionamento do load balancer, emissão do certificado,
  redirect e as cinco rotas respondendo): validado na nuvem: pendente.
