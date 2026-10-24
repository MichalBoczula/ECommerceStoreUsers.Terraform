resource "azurerm_container_app" "users" {
  count                        = var.deploy_users_app ? 1 : 0
  name                         = local.names.app
  resource_group_name          = azurerm_resource_group.users.name
  container_app_environment_id = data.azurerm_container_app_environment.shared.id
  workload_profile_name        = "Consumption"
  revision_mode                = "Single"
  tags                         = local.tags
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.users.id]
  }
  secret {
    name                = "users-mongo-connection"
    identity            = azurerm_user_assigned_identity.users.id
    key_vault_secret_id = azurerm_key_vault_secret.users_mongo.versionless_id
  }
  ingress {
    external_enabled           = var.users_external_ingress_enabled
    allow_insecure_connections = false
    target_port                = 8080
    transport                  = "http"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
    dynamic "ip_security_restriction" {
      for_each = var.users_external_ingress_enabled ? [var.api_operator_ipv4] : []
      content {
        name             = "operator-only"
        action           = "Allow"
        description      = "Temporary Users API verification from the operator address."
        ip_address_range = "${ip_security_restriction.value}/32"
      }
    }
  }
  template {
    min_replicas = var.min_replicas
    max_replicas = 1
    http_scale_rule {
      name                = "http"
      concurrent_requests = "10"
    }
    container {
      name   = "users"
      image  = var.users_image
      cpu    = 0.25
      memory = "0.5Gi"
      env {
        name        = "MongoDbSettings__ConnectionString"
        secret_name = "users-mongo-connection"
      }
      dynamic "env" {
        for_each = local.container_environment
        content {
          name  = env.key
          value = env.value
        }
      }
      startup_probe {
        transport               = "HTTP"
        port                    = 8080
        path                    = "/health/live"
        interval_seconds        = 5
        timeout                 = 3
        failure_count_threshold = 60
      }
      liveness_probe {
        transport               = "HTTP"
        port                    = 8080
        path                    = "/health/live"
        interval_seconds        = 30
        timeout                 = 3
        failure_count_threshold = 3
      }
      readiness_probe {
        transport               = "HTTP"
        port                    = 8080
        path                    = local.serving ? "/health/ready" : "/health/live"
        interval_seconds        = 10
        timeout                 = 7
        success_count_threshold = 1
        failure_count_threshold = 3
      }
    }
  }
  depends_on = [azurerm_role_assignment.users_secrets, azapi_resource.users_egress]
  lifecycle {
    precondition {
      condition     = !var.users_external_ingress_enabled || (!data.azurerm_container_app_environment.shared.internal_load_balancer_enabled && data.azurerm_container_app_environment.shared.public_network_access == "Enabled")
      error_message = "External testing requires an externally reachable shared ACA environment."
    }
  }
}
