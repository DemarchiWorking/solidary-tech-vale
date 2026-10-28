mock_provider "google" {}

variables {
  project_id            = "solidarytech-test"
  project_number        = "123456789012"
  name                  = "solidarytech"
  workload_pool         = "solidarytech-test.svc.id.goog"
  events_topic          = "donation-events"
  consumer_subscription = "notification-service"
  dr_bucket             = "solidarytech-test-solidarytech-dr"
}

run "principals_usam_numero_do_projeto" {
  command = plan

  assert {
    condition     = google_pubsub_topic_iam_member.donation_publisher.member == "principal://iam.googleapis.com/projects/123456789012/locations/global/workloadIdentityPools/solidarytech-test.svc.id.goog/subject/ns/donation/sa/donation-service"
    error_message = "O principal da KSA do donation-service está no formato errado."
  }
  assert {
    condition     = google_pubsub_subscription_iam_member.notification_subscriber.role == "roles/pubsub.subscriber"
    error_message = "notification-service precisa consumir a assinatura."
  }
  assert {
    condition     = length(google_project_iam_member.firestore_user) == 2
    error_message = "notification e volunteer precisam de datastore.user."
  }
}

run "velero_por_gsa_anotada" {
  command = plan

  assert {
    condition     = google_service_account_iam_member.velero_workload_identity.member == "serviceAccount:solidarytech-test.svc.id.goog[velero/velero-server]"
    error_message = "A KSA do Velero no chart 12.x é velero/velero-server."
  }
  assert {
    condition     = google_service_account_iam_member.velero_sign_blob.role == "roles/iam.serviceAccountTokenCreator"
    error_message = "O Velero precisa de signBlob na própria GSA."
  }
}
