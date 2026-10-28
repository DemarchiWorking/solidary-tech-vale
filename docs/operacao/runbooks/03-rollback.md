# Runbook 03. Rollback de um serviço

Quando uma versão nova de um serviço piora erro ou latência. O estado
desejado está no Git, então o rollback também passa pelo Git; mexer direto
no cluster é desfeito pelo self-heal do ArgoCD em minutos.

## Caminho normal: reverter o commit da tag

1. Ache o commit do CI que trocou a imagem:

   ```bash
   git log --oneline -5 -- deploy/gitops/apps/<app>/overlays/prod/kustomization.yaml
   ```

   As mensagens têm a forma `deploy: update <serviço> to <sha>`.

2. Reverta e publique:

   ```bash
   git revert --no-edit <commit-do-deploy> && git push origin main
   ```

3. O ArgoCD sincroniza a tag anterior. Acompanhe:

   ```bash
   kubectl -n <app> rollout status deployment/<serviço>
   ```

A imagem anterior ainda está no Artifact Registry: a limpeza guarda as 20
versões mais recentes de cada imagem.

## Caminho rápido: rollback pelo ArgoCD

Para ganhar minutos enquanto o revert não entra:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Na interface, abra `app-<app>`, desligue o auto-sync, use History and
Rollback e escolha a revisão anterior. Depois faça o revert do passo 2 e
religue o auto-sync; se o auto-sync ficar desligado, o próximo deploy não
entra.

## Se o problema for o código, não a versão

Corrija no código e deixe o CI publicar uma tag nova; o revert só serve
para voltar ao último estado bom.

## Banco

Os `db/init.sql` só criam tabelas que não existem; não há migração
destrutiva no deploy. Se uma versão gravou dados errados, o caminho é o
PITR do Cloud SQL ([runbook 04](04-restore-velero.md#cloud-sql-pitr)).

## Conferir

- O monitor de 5xx e o de p95 do serviço voltam a OK no Datadog.
- `kubectl -n <app> get deployment <serviço> -o jsonpath='{.spec.template.spec.containers[0].image}'`
  mostra a tag anterior.
