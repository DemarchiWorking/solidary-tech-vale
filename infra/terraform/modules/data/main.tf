# ============================================
# Dados: Cloud SQL (PostgreSQL), Pub/Sub, Firestore e bucket de DR
# ============================================

locals {
  pubsub_agent = "serviceAccount:service-${var.project_number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

# --------------------------------------------------------------------
# Cloud SQL — PostgreSQL 15, HA regional, só IP privado
# --------------------------------------------------------------------
# O nome leva um sufixo aleatório porque o Cloud SQL não deixa reusar o nome
# de uma instância por cerca de uma semana depois de excluída.
resource "random_id" "sql" {
  byte_length = 3
}

resource "google_sql_database_instance" "main" {
  project             = var.project_id
  name                = "${var.name}-pg-${random_id.sql.hex}"
  region              = var.region
  database_version    = "POSTGRES_15"
  deletion_protection = var.deletion_protection

  settings {
    edition                     = "ENTERPRISE"
    tier                        = var.sql_tier
    availability_type           = var.sql_availability_type
    disk_type                   = "PD_SSD"
    disk_size                   = 20
    disk_autoresize             = true
    deletion_protection_enabled = var.deletion_protection
    user_labels                 = merge(var.labels, { component = "database" })

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.network_id
      ssl_mode                                      = "ENCRYPTED_ONLY"
      enable_private_path_for_google_cloud_services = true
    }

    # PITR de 7 dias (RPO de minutos para falha lógica ou zonal) e backups
    # diários guardados na região de DR (restauráveis se a região cair).
    backup_configuration {
      enabled                        = true
      start_time                     = "04:00"
      location                       = var.backup_region
      point_in_time_recovery_enabled = true
      transaction_log_retention_days = 7
      backup_retention_settings {
        retained_backups = 14
        retention_unit   = "COUNT"
      }
    }

    maintenance_window {
      day  = 7
      hour = 5
    }

    insights_config {
      query_insights_enabled = true
    }
  }
}

resource "google_sql_database" "db" {
  for_each = toset(var.databases)

  project  = var.project_id
  name     = each.value
  instance = google_sql_database_instance.main.name
}

# Um usuário por serviço: credenciais separadas para rotacionar e auditar.
# Os usuários criados pela API entram no papel cloudsqlsuperuser; isolar
# privilégios exige GRANT/REVOKE dentro do banco (ver docs/arquitetura).
resource "random_password" "sql_user" {
  for_each = var.sql_users

  length  = 32
  special = false
}

resource "google_sql_user" "app" {
  for_each = var.sql_users

  project  = var.project_id
  instance = google_sql_database_instance.main.name
  name     = each.key
  password = random_password.sql_user[each.key].result
}

# --------------------------------------------------------------------
# Pub/Sub — eventos de doação, com retry e DLQ
# --------------------------------------------------------------------
resource "google_pubsub_topic" "events" {
  project                    = var.project_id
  name                       = var.events_topic
  message_retention_duration = "604800s"
  labels                     = merge(var.labels, { component = "messaging" })
}

resource "google_pubsub_topic" "dlq" {
  project                    = var.project_id
  name                       = "${var.events_topic}-dlq"
  message_retention_duration = "604800s"
  labels                     = merge(var.labels, { component = "messaging" })
}

resource "google_pubsub_subscription" "consumer" {
  project = var.project_id
  name    = var.consumer_subscription
  topic   = google_pubsub_topic.events.id

  ack_deadline_seconds       = 60
  message_retention_duration = "604800s"

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  # Mesmo limite do max_delivery_count do Service Bus da versão Azure.
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = var.max_delivery_attempts
  }

  expiration_policy {
    ttl = ""
  }

  labels = merge(var.labels, { component = "messaging" })
}

# Sem uma assinatura, o que cai na DLQ se perde.
resource "google_pubsub_subscription" "dlq" {
  project                    = var.project_id
  name                       = "${var.events_topic}-dlq-inspecao"
  topic                      = google_pubsub_topic.dlq.id
  ack_deadline_seconds       = 60
  message_retention_duration = "604800s"

  expiration_policy {
    ttl = ""
  }

  labels = merge(var.labels, { component = "messaging" })
}

# O agente do Pub/Sub é quem move a mensagem para a DLQ: precisa publicar na
# DLQ e confirmar a mensagem na assinatura de origem.
resource "google_pubsub_topic_iam_member" "dlq_publisher" {
  project = var.project_id
  topic   = google_pubsub_topic.dlq.name
  role    = "roles/pubsub.publisher"
  member  = local.pubsub_agent
}

resource "google_pubsub_subscription_iam_member" "dlq_subscriber" {
  project      = var.project_id
  subscription = google_pubsub_subscription.consumer.name
  role         = "roles/pubsub.subscriber"
  member       = local.pubsub_agent
}

# Alerta nativo: qualquer mensagem na DLQ precisa de alguém olhando.
resource "google_monitoring_alert_policy" "dlq_backlog" {
  project      = var.project_id
  display_name = "SolidaryTech - mensagens na DLQ de doações"
  combiner     = "OR"

  conditions {
    display_name = "DLQ com mensagens não entregues"
    condition_threshold {
      filter          = "resource.type = \"pubsub_subscription\" AND resource.labels.subscription_id = \"${google_pubsub_subscription.dlq.name}\" AND metric.type = \"pubsub.googleapis.com/subscription/num_undelivered_messages\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "300s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  notification_channels = var.alert_notification_channels
  user_labels           = var.labels
}

# --------------------------------------------------------------------
# Firestore — voluntários e notificações processadas
# --------------------------------------------------------------------
resource "google_firestore_database" "this" {
  project                           = var.project_id
  name                              = "(default)"
  location_id                       = var.firestore_location
  type                              = "FIRESTORE_NATIVE"
  concurrency_mode                  = "OPTIMISTIC"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  delete_protection_state           = var.deletion_protection ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  deletion_policy                   = "DELETE"
}

resource "google_firestore_backup_schedule" "daily" {
  project   = var.project_id
  database  = google_firestore_database.this.name
  retention = "604800s"

  daily_recurrence {}
}

# --------------------------------------------------------------------
# Bucket de DR (região secundária): backups do Velero e exports do
# Firestore. O backup gerenciado do Firestore só restaura na mesma região;
# o export diário é o que permite recuperar em outra.
# --------------------------------------------------------------------
resource "google_storage_bucket" "dr" {
  project                     = var.project_id
  name                        = "${var.project_id}-${var.name}-dr"
  location                    = var.backup_region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = !var.deletion_protection
  labels                      = merge(var.labels, { component = "disaster-recovery" })

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 120
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_service_account" "firestore_export" {
  project      = var.project_id
  account_id   = "${var.name}-fs-export"
  display_name = "Export diário do Firestore para o bucket de DR"
}

resource "google_project_iam_member" "firestore_export" {
  project = var.project_id
  role    = "roles/datastore.importExportAdmin"
  member  = "serviceAccount:${google_service_account.firestore_export.email}"
}

resource "google_storage_bucket_iam_member" "firestore_export" {
  bucket = google_storage_bucket.dr.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.firestore_export.email}"
}

resource "google_cloud_scheduler_job" "firestore_export" {
  project     = var.project_id
  region      = var.region
  name        = "${var.name}-firestore-export"
  description = "Export diário do Firestore para gs://${google_storage_bucket.dr.name}/firestore"
  schedule    = var.firestore_export_schedule
  time_zone   = "America/Sao_Paulo"

  http_target {
    http_method = "POST"
    uri         = "https://firestore.googleapis.com/v1/projects/${var.project_id}/databases/${google_firestore_database.this.name}:exportDocuments"
    body        = base64encode(jsonencode({ outputUriPrefix = "gs://${google_storage_bucket.dr.name}/firestore" }))
    headers = {
      "Content-Type" = "application/json"
    }
    oauth_token {
      service_account_email = google_service_account.firestore_export.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [
    google_project_iam_member.firestore_export,
    google_storage_bucket_iam_member.firestore_export,
  ]
}
