# ADR 0002. Monorepo reorganizado e IaC Azure fora da branch-gcp

Status: aceita (branch-gcp)

## Contexto

O monorepo `solidary-tech-vale` juntou seis repositórios (`fiap-tc-5-*`)
mantendo os nomes de pasta originais. Para a versão GCP, o código, a IaC e o
GitOps precisam ficar fáceis de achar, e o CI precisa saber exatamente qual
pasta dispara qual workflow.

## Decisão

- Árvore por responsabilidade: `services/` (código), `infra/terraform/`
  (IaC), `deploy/gitops/` (o que o ArgoCD aplica), `scripts/` e `docs/`.
  Os movimentos foram feitos com `git mv`. O mapa completo, arquivo a
  arquivo, está em [nova-arvore.md](../../migracao/nova-arvore.md).
- A IaC Azure (`fiap-tc-5-terraform`) não entra na `branch-gcp`. Ela continua
  intacta na `main` e na `branch-azure`.
- Os adaptadores Azure do código continuam (ver
  [ADR 0003](0003-adaptadores-por-cloud-provider.md)).

Tirei a IaC Azure porque manter duas IaCs na mesma branch, com um GitOps que
só serve para GKE (Gateway API, Workload Identity, plugin do Velero para
GCP), deixaria metade do repositório sem caminho de deploy e induziria a
erro. Quem precisar da versão Azure tem a branch inteira, coerente.

## Consequências

- Os `paths` dos workflows passam a ser `services/<serviço>/**`, e o
  ApplicationSet tira o nome do app do segmento 3 de
  `deploy/gitops/apps/<app>/overlays/prod` (`index .path.segments 3` em
  `deploy/gitops/applicationsets/apps-appset.yaml`).
- O ArgoCD acompanha a branch padrão (`targetRevision: HEAD`). A
  `branch-gcp` precisa virar a `main` (merge) antes do primeiro deploy na
  nuvem; até lá, o CI testa a `branch-gcp`, mas não publica imagem.
