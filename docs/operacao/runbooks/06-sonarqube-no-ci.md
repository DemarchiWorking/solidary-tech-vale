# Runbook 06. SonarQube no CI: cadastrar e atualizar

O job `SonarQube Scan` dos 4 CIs (`.github/workflows/<serviço>-ci.yaml`) lê
dois secrets do repositório: `SONAR_TOKEN` e `SONAR_HOST_URL`. Sem os dois,
o job mostra o aviso "SONAR_TOKEN ou SONAR_HOST_URL não cadastrado; análise
do SonarQube pulada." e termina sem falhar.

O SonarQube é o do próprio cluster (addon `deploy/gitops/addons/sonarqube`,
Community Build, chart 2026.4.1), servido em `https://<host>/sonarqube`. Por
isso este runbook vem depois do [runbook 02](02-primeiro-deploy.md): antes
de o cluster existir, não há SonarQube para apontar, e o job continua pulado.

## Antes

- O app `addon-sonarqube` está `Synced` e `Healthy` no ArgoCD.
- O certificado do Gateway está `ACTIVE` (passo 5 do runbook 02).
- Você tem `kubectl` no cluster (passo 3 do runbook 02).

## 1. Descobrir a URL

Na raiz do repositório:

```bash
HOST=$(terraform -chdir=infra/terraform/envs/prod/infra output -raw gateway_hostname)
```

```bash
echo "https://$HOST/sonarqube"
```

```bash
curl -fsS "https://$HOST/sonarqube/api/system/status"
```

A resposta tem `"status":"UP"`. Guarde a URL, sem barra no fim: ela é o
valor de `SONAR_HOST_URL`.

## 2. Entrar como administrador

A senha do `admin` foi gerada pelo Terraform e aplicada pelo chart (a
senha padrão `admin` não vale mais):

```bash
kubectl -n sonarqube get secret sonarqube-admin -o jsonpath='{.data.password}' | base64 -d
```

Abra a URL do passo 1 e entre com o usuário `admin` e essa senha.

## 3. Criar um usuário só para o CI

O token do CI não deve ser do `admin`.

1. Administration > Security > Users > Create User.
2. Login `ci-github`, nome `GitHub Actions`, uma senha forte (guarde no seu
   gerenciador de senhas; ela só serve para gerar o token).
3. Administration > Security > Global Permissions: marque **Execute
   Analysis** para o `ci-github`.

## 4. Criar os 4 projetos

Os nomes precisam ser exatamente os `sonar.projectKey` dos workflows. Para
cada um: Projects > Create Project > Local project.

| Project display name | Project key | Main branch name |
|---|---|---|
| donation-service | `donation-service` | `main` |
| ngo-service | `ngo-service` | `main` |
| volunteer-service | `volunteer-service` | `main` |
| notification-service | `notification-service` | `main` |

Na tela seguinte, escolha "Use the global setting" para o código novo e
pare por aí: não gere o token sugerido pelo assistente, que vale para um
projeto só.

## 5. Gerar o token

1. Saia do `admin` e entre como `ci-github`.
2. My Account > Security > Generate Tokens.
3. Name `github-actions-solidary-tech`, Type **Global Analysis Token**
   (um token serve para os 4 projetos), Expires in 90 days.
4. Copie o token: ele aparece uma vez só. Anote a data de expiração.

## 6. Cadastrar no GitHub

No repositório `DemarchiWorking/solidary-tech-vale`: Settings > Secrets and
variables > Actions > aba **Secrets** > New repository secret.

| Name | Secret |
|---|---|
| `SONAR_TOKEN` | o token do passo 5 |
| `SONAR_HOST_URL` | a URL do passo 1, por exemplo `https://34-95-10-20.sslip.io/sonarqube` |

São secrets do repositório, não do environment `production`: o job do
SonarQube não usa environment.

Com o `gh` logado, dá para fazer o mesmo pelo terminal. O primeiro comando
pede o valor sem ecoar e sem deixar no histórico do shell:

```bash
gh secret set SONAR_TOKEN --repo DemarchiWorking/solidary-tech-vale
```

```bash
gh secret set SONAR_HOST_URL --repo DemarchiWorking/solidary-tech-vale --body "https://$HOST/sonarqube"
```

## 7. Testar

Actions > `CI - ngo-service` > Run workflow, branch `main`. No job
`SonarQube Scan`, o passo de aviso aparece como pulado e o passo
`SonarQube Scan` roda; o log termina com o link do painel do projeto
(`/sonarqube/dashboard?id=ngo-service`). No SonarQube, o projeto passa a
mostrar issues e cobertura. Repita para os outros três serviços, ou espere
o próximo push que mexa em cada um.

## Atualizar

### Token novo (expirou, vazou ou é hora de rodar)

1. Gere um token novo como no passo 5.
2. GitHub: Settings > Secrets and variables > Actions > `SONAR_TOKEN` >
   ícone de lápis (Update) > cole o valor novo > Update secret. Ou
   `gh secret set SONAR_TOKEN --repo DemarchiWorking/solidary-tech-vale`.
3. Rode um CI (passo 7) para confirmar.
4. No SonarQube, como `ci-github`: My Account > Security > Revoke no token
   antigo.

Token vencido ou revogado aparece como erro de autenticação (401, "Not
authorized") no passo `SonarQube Scan`.

### Endereço novo (domínio próprio, IP novo, failover)

Atualize `SONAR_HOST_URL` do mesmo jeito, com a URL nova e o sufixo
`/sonarqube`. O token continua valendo se o SonarQube for o mesmo; no
failover para o DR, o SonarQube do cluster novo é outra instância, então
refaça os passos 2 a 6 nele.

### Tirar o SonarQube do CI

Apague os dois secrets. O job volta a mostrar o aviso e passa.

## Limites

- A Community Build analisa só a branch principal. Análises vindas de PR
  e da `branch-gcp` entram no mesmo projeto e substituem a anterior. Análise
  separada por branch e comentário no PR exigem Developer Edition ou
  SonarQube Cloud.
- O passo não espera o Quality Gate: um gate vermelho não falha o CI. Para
  bloquear, acrescente `-Dsonar.qualitygate.wait=true` aos `args` do passo
  `SonarQube Scan`.
