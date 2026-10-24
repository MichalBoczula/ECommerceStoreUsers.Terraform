output "users_foundation" {
  description = "Non-secret foundation references. Products owns the shared environment and network."
  value = {
    subscription_id             = var.subscription_id
    resource_group_name         = azurerm_resource_group.users.name
    location                    = azurerm_resource_group.users.location
    aca_environment_id          = data.azurerm_container_app_environment.shared.id
    aca_environment_name        = data.azurerm_container_app_environment.shared.name
    aca_subnet_id               = data.azurerm_container_app_environment.shared.infrastructure_subnet_id
    identity_id                 = azurerm_user_assigned_identity.users.id
    key_vault_name              = azurerm_key_vault.users.name
    mongo_connection_secret_uri = azurerm_key_vault_secret.users_mongo.versionless_id
    documentdb_id               = azapi_resource.documentdb.id
    documentdb_name             = azapi_resource.documentdb.name
    documentdb_location         = var.documentdb_location
    documentdb_tier             = "Free"
    documentdb_storage_gb       = 32
    mongo_database_name         = local.mongo_database_name
  }
}

output "users_deployment" {
  description = "Non-secret runtime details; internal base_url works from the shared environment only."
  value = {
    enabled               = var.deploy_users_app
    name                  = local.names.app
    resource_group_name   = azurerm_resource_group.users.name
    base_url              = try("https://${azurerm_container_app.users[0].ingress[0].fqdn}", null)
    stage                 = var.users_deployment_stage
    initialize_on_startup = local.serving
    external_ingress      = var.users_external_ingress_enabled
    image                 = var.users_image
    min_replicas          = var.min_replicas
    outbound_ipv4         = try(azurerm_container_app.users[0].outbound_ip_addresses, [])
    mongo_firewall_ipv4   = var.users_mongo_egress_ipv4
  }
}

output "resource_names" {
  value = local.names
}
