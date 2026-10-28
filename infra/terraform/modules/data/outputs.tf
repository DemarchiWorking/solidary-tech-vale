output "sql_instance_name" {
  value = google_sql_database_instance.main.name
}

output "sql_connection_name" {
  value = google_sql_database_instance.main.connection_name
}

output "sql_private_ip" {
  value = google_sql_database_instance.main.private_ip_address
}

output "sql_user_passwords" {
  description = "Senha de cada usuário de serviço"
  value       = { for k, p in random_password.sql_user : k => p.result }
  sensitive   = true
}

output "sql_users" {
  value = var.sql_users
}

output "events_topic" {
  value = google_pubsub_topic.events.name
}

output "events_topic_id" {
  value = google_pubsub_topic.events.id
}

output "consumer_subscription" {
  value = google_pubsub_subscription.consumer.name
}

output "consumer_subscription_id" {
  value = google_pubsub_subscription.consumer.id
}

output "dlq_subscription" {
  value = google_pubsub_subscription.dlq.name
}

output "firestore_database" {
  value = google_firestore_database.this.name
}

output "dr_bucket" {
  value = google_storage_bucket.dr.name
}
