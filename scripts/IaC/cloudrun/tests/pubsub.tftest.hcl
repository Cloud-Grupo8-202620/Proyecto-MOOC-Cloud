# Suscripción push autenticada, ack deadline, reintentos y dead-letter.

mock_provider "google" {
  source = "./tests/mocks"
}
mock_provider "random" {}

variables {
  project_id = "proyecto-test"
  image_tag  = "abc123def456"
}

run "suscripcion_push_autenticada" {
  command = apply

  assert {
    condition     = google_pubsub_subscription.jobs.ack_deadline_seconds == 600
    error_message = "El ack deadline debe ser 600 s, el máximo de Pub/Sub"
  }

  assert {
    condition     = endswith(google_pubsub_subscription.jobs.push_config[0].push_endpoint, "/pubsub/push")
    error_message = "La suscripción debe apuntar al endpoint de push del worker"
  }

  assert {
    condition     = length(google_pubsub_subscription.jobs.push_config[0].oidc_token) == 1
    error_message = "La entrega push debe usar OIDC"
  }

  assert {
    condition     = google_pubsub_subscription.jobs.push_config[0].oidc_token[0].service_account_email == google_service_account.role["pubsub_push"].email
    error_message = "El token OIDC debe firmarlo la cuenta push dedicada"
  }
}

run "reintentos_y_dead_letter" {
  command = apply

  assert {
    condition     = google_pubsub_subscription.jobs.retry_policy[0].minimum_backoff == "10s"
    error_message = "El backoff mínimo debe ser 10 s"
  }

  assert {
    condition     = google_pubsub_subscription.jobs.retry_policy[0].maximum_backoff == "600s"
    error_message = "El backoff máximo debe ser 600 s"
  }

  assert {
    condition     = google_pubsub_subscription.jobs.dead_letter_policy[0].max_delivery_attempts == 5
    error_message = "El dead-letter debe activarse a los 5 intentos"
  }

  assert {
    condition     = google_pubsub_subscription.jobs.dead_letter_policy[0].dead_letter_topic == google_pubsub_topic.dlq.id
    error_message = "La suscripción debe apuntar al topic DLQ"
  }

  assert {
    condition     = google_pubsub_subscription.jobs.expiration_policy[0].ttl == ""
    error_message = "La suscripción no debe expirar por inactividad"
  }
}

run "worker_solo_invokable_por_la_suscripcion" {
  command = apply

  assert {
    condition     = google_cloud_run_v2_service_iam_member.worker_push.member == google_service_account.role["pubsub_push"].member
    error_message = "Solo la cuenta push debe poder invocar el worker"
  }

  assert {
    condition     = google_cloud_run_v2_service_iam_member.frontend_public.member == "allUsers"
    error_message = "El frontend es público"
  }

  assert {
    condition     = google_cloud_run_v2_service_iam_member.backend_public.member == "allUsers"
    error_message = "El backend es público; la autenticación la valida la API"
  }
}
