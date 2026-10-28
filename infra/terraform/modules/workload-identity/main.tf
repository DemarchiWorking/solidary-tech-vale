# ============================================
# Workload Identity: permissões dos pods, sem chave
# ============================================
# Cada serviço roda com a sua KSA (ServiceAccount do Kubernetes, definida no
# GitOps) e recebe papel direto no recurso que usa, pelo identificador
# principal:// da KSA. O pool <projeto>.svc.id.goog só passa a existir
# depois que o primeiro cluster com Workload Identity é criado; por isso o
# pool chega aqui como output do módulo gke (var.workload_pool), o que faz
# o Terraform criar estes bindings só depois do cluster.

locals {
  principal = {
    for app, ksa in var.apps :
    app => "principal://iam.googleapis.com/projects/${var.project_number}/locations/global/workloadIdentityPools/${var.workload_pool}/subject/ns/${ksa.namespace}/sa/${ksa.name}"
  }
}

# donation-service publica os eventos de doação.
resource "google_pubsub_topic_iam_member" "donation_publisher" {
  project = var.project_id
  topic   = var.events_topic
  role    = "roles/pubsub.publisher"
  member  = local.principal["donation"]
}

# notification-service consome a assinatura e grava no Firestore.
resource "google_pubsub_subscription_iam_member" "notification_subscriber" {
  project      = var.project_id
  subscription = var.consumer_subscription
  role         = "roles/pubsub.subscriber"
  member       = local.principal["notification"]
}

# O IAM do Firestore é por projeto (não há papel por coleção).
resource "google_project_iam_member" "firestore_user" {
  for_each = toset(["notification", "volunteer"])

  project = var.project_id
  role    = "roles/datastore.user"
  member  = local.principal[each.value]
}

# --- Velero: o plugin do GCP usa uma GSA via anotação na KSA velero-server ---
resource "google_service_account" "velero" {
  project      = var.project_id
  account_id   = "${var.name}-velero"
  display_name = "Velero (backups do cluster para o bucket de DR)"
}

resource "google_storage_bucket_iam_member" "velero_bucket" {
  bucket = var.dr_bucket
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.velero.email}"
}

# signBlob na própria GSA: o Velero assina URLs para download/describe.
resource "google_service_account_iam_member" "velero_sign_blob" {
  service_account_id = google_service_account.velero.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${google_service_account.velero.email}"
}

resource "google_service_account_iam_member" "velero_workload_identity" {
  service_account_id = google_service_account.velero.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.workload_pool}[${var.velero_namespace}/${var.velero_ksa}]"
}
