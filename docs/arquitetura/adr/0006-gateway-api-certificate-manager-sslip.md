# ADR 0006. Gateway API, Certificate Manager e host sslip.io

Status: aceita (branch-gcp)

## Contexto

Na `main`, a exposição era ingress-nginx atrás de um Load Balancer do Azure,
com um Ingress por serviço. O projeto não tem domínio próprio.

## Decisão

- Um Gateway só, classe `gke-l7-global-external-managed` (load balancer
  global de aplicação do Google), em `deploy/gitops/addons/gateway/manifests/gateway.yaml`.
  O IP é um endereço global reservado pelo Terraform e referenciado pelo
  nome (`NamedAddress`, `solidarytech-gateway-ip`).
- HTTPS com certificado gerenciado do Certificate Manager, ligado ao Gateway
  pela anotação `networking.gke.io/certmap`. O listener HTTPS não tem bloco
  `tls`, como a documentação do GKE exige quando se usa certmap.
- Host `<ip-com-hifens>.sslip.io`, que resolve para o próprio IP sem DNS
  próprio (`infra/terraform/modules/edge/main.tf`). Com a variável
  `hostname`, o mesmo módulo usa um domínio próprio.
- Certificado com autorização por load balancer (sem `dns_authorizations`):
  o Google emite quando o Gateway estiver servindo nesse IP.
- HTTP redireciona para HTTPS (`http-redirect.yaml`).
- Rotas por prefixo, cada uma no namespace do serviço, presas ao listener
  `https`: `/donations`, `/ngos`, `/volunteers`, `/grafana`, `/sonarqube`.
  Só namespaces com a label `solidarytech.io/gateway=true` (criada pelo
  Terraform em `modules/platform`) podem pendurar rotas.
- `HealthCheckPolicy` por Service apontando para `/health`, porque o health
  check padrão do load balancer usa `/` e os serviços não respondem ali.

## Consequências

- Sem controlador de ingress para manter no cluster.
- A emissão do certificado pode levar perto de 1 hora depois do primeiro
  sync do Gateway; até lá o HTTPS não responde (runbook 02).
- sslip.io é um serviço de terceiros; para produção com marca própria, basta
  preencher `hostname` e criar o registro DNS.
- Provisionamento do Gateway e emissão do certificado: validado na nuvem:
  pendente. Localmente, os manifests passam no `kubeconform` com os schemas
  das CRDs do Gateway API e do GKE (`scripts/ci/gitops-check.sh`).
