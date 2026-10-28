locals {
  prefix = "${var.project_name}-${var.environment}"

  # Monorepo no GitHub (var.github_owner/var.github_repo): o ArgoCD lê o
  # GitOps dele e os webhooks de self-healing disparam nele, cada serviço
  # com o seu event_type. var.gitops_repo e var.service_repos sobrescrevem.
  github_repo = "${var.github_owner}/${var.github_repo}"
  gitops_repo = coalesce(var.gitops_repo, local.github_repo)
  service_repos = merge(
    { for s in ["ngo-service", "donation-service", "volunteer-service", "notification-service"] : s => local.github_repo },
    var.service_repos,
  )

  # ------------------------------------------------------------------
  # FinOps: Estratégia de Tagging (requisito obrigatório da Fase 5)
  # ------------------------------------------------------------------
  # Tags obrigatórias exigidas no desafio, aplicadas em 100% dos recursos
  # de nuvem via `local.tags` (ou `merge(local.tags, {...})` quando o
  # recurso precisa de uma tag extra, ex.: Component). Isso é o que
  # sustenta a análise de custo por projeto/ambiente/centro de custo no
  # Cost Management do Azure (relatório de Forecast).
  mandatory_tags = {
    Project     = "SolidaryTech"
    Environment = "Production"
    CostCenter  = "NGO-Core"
  }

  tags = merge(local.mandatory_tags, {
    ManagedBy = "terraform"
    Fase      = "5"
  })
}

# ============================================
# Resource Group
# ============================================

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.prefix}"
  location = var.location
  tags     = merge(local.tags, { Component = "core" })
}
