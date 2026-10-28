mock_provider "google" {}
mock_provider "random" {}

variables {
  project_id         = "solidarytech-test"
  project_number     = "123456789012"
  name               = "solidarytech"
  region             = "southamerica-east1"
  backup_region      = "southamerica-west1"
  network_id         = "projects/solidarytech-test/global/networks/solidarytech-vpc"
  firestore_location = "southamerica-east1"
}

run "cloud_sql_ha_privado_com_pitr" {
  command = plan

  assert {
    condition     = google_sql_database_instance.main.settings[0].availability_type == "REGIONAL"
    error_message = "Cloud SQL precisa de HA regional."
  }
  assert {
    condition     = google_sql_database_instance.main.settings[0].ip_configuration[0].ipv4_enabled == false
    error_message = "Cloud SQL não pode ter IP público."
  }
  assert {
    condition     = google_sql_database_instance.main.settings[0].ip_configuration[0].ssl_mode == "ENCRYPTED_ONLY"
    error_message = "Conexões ao banco precisam ser cifradas (sslmode=require)."
  }
  assert {
    condition     = google_sql_database_instance.main.settings[0].backup_configuration[0].point_in_time_recovery_enabled
    error_message = "PITR precisa estar ligado (RPO de minutos)."
  }
  assert {
    condition     = google_sql_database_instance.main.settings[0].backup_configuration[0].location == "southamerica-west1"
    error_message = "Backups precisam ficar na região de DR."
  }
  assert {
    condition     = length(google_sql_database.db) == 3 && length(google_sql_user.app) == 3
    error_message = "Três bancos (ngo_db, donation_db, sonarqube) e um usuário por serviço."
  }
}

run "pubsub_com_dlq_e_permissao_do_agente" {
  command = plan

  assert {
    condition     = google_pubsub_subscription.consumer.dead_letter_policy[0].max_delivery_attempts == 10
    error_message = "DLQ depois de 10 tentativas (igual ao Service Bus da versão Azure)."
  }
  assert {
    condition     = google_pubsub_subscription.consumer.ack_deadline_seconds == 60
    error_message = "Ack deadline de 60 s."
  }
  assert {
    condition     = google_pubsub_topic_iam_member.dlq_publisher.member == "serviceAccount:service-123456789012@gcp-sa-pubsub.iam.gserviceaccount.com"
    error_message = "O agente do Pub/Sub (pelo número do projeto) precisa publicar na DLQ."
  }
  assert {
    condition     = google_pubsub_subscription_iam_member.dlq_subscriber.role == "roles/pubsub.subscriber"
    error_message = "O agente do Pub/Sub precisa confirmar a mensagem na assinatura de origem."
  }
  assert {
    condition     = google_pubsub_subscription.dlq.name == "donation-events-dlq-inspecao"
    error_message = "A DLQ precisa de uma assinatura, senão as mensagens se perdem."
  }
}

run "firestore_e_dr" {
  command = plan

  assert {
    condition     = google_firestore_database.this.point_in_time_recovery_enablement == "POINT_IN_TIME_RECOVERY_ENABLED"
    error_message = "Firestore precisa de PITR."
  }
  assert {
    condition     = google_firestore_database.this.delete_protection_state == "DELETE_PROTECTION_ENABLED"
    error_message = "Firestore protegido contra exclusão por padrão."
  }
  assert {
    condition     = google_storage_bucket.dr.location == "southamerica-west1" && google_storage_bucket.dr.public_access_prevention == "enforced"
    error_message = "Bucket de DR na região secundária e sem acesso público."
  }
  assert {
    condition     = strcontains(google_cloud_scheduler_job.firestore_export.http_target[0].uri, ":exportDocuments")
    error_message = "O export diário do Firestore precisa chamar exportDocuments."
  }
}
