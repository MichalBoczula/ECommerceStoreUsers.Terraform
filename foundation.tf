# Products owns the environment, its delegated subnet and VNet. This stack only reads them.
data "azurerm_container_app_environment" "shared" {
  name                = local.shared_environment.name
  resource_group_name = local.shared_environment.resource_group_name
}

resource "azurerm_resource_group" "users" {
  name     = local.names.resource_group
  location = data.azurerm_container_app_environment.shared.location
  tags     = local.tags
}

resource "azurerm_user_assigned_identity" "users" {
  name                = local.names.identity
  location            = azurerm_resource_group.users.location
  resource_group_name = azurerm_resource_group.users.name
  tags                = local.tags
}

resource "azurerm_key_vault" "users" {
  name                          = local.names.key_vault
  location                      = azurerm_resource_group.users.location
  resource_group_name           = azurerm_resource_group.users.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  soft_delete_retention_days    = 7
  purge_protection_enabled      = false
  public_network_access_enabled = true
  tags                          = local.tags
}

resource "azurerm_role_assignment" "operator_secrets" {
  scope                = azurerm_key_vault.users.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.operator_object_id
}

resource "azurerm_role_assignment" "users_secrets" {
  scope                            = azurerm_key_vault.users.id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = azurerm_user_assigned_identity.users.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_key_vault_secret" "users_mongo" {
  name         = "users-mongo-connection"
  value        = local.mongo_connection
  key_vault_id = azurerm_key_vault.users.id
  content_type = "MongoDB connection string"
  tags         = local.tags
  depends_on   = [azurerm_role_assignment.operator_secrets]
  lifecycle {
    precondition {
      condition     = length(local.mongo_templates) > 0 && length(local.mongo_username) > 0
      error_message = "DocumentDB must return its assigned administrator and a native-auth SRV connection template. Do not guess the username or endpoint."
    }
  }
}
