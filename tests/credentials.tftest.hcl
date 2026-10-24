mock_provider "azurerm" { override_during = apply }
mock_provider "azapi" { override_during = apply }

override_data {
  target          = data.azurerm_client_config.current
  override_during = apply
  values          = { tenant_id = "11111111-1111-1111-1111-111111111111" }
}
override_data {
  target          = data.azurerm_container_app_environment.shared
  override_during = apply
  values = {
    id                             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-products-dev/providers/Microsoft.App/managedEnvironments/cae-ecommercestore-products-dev"
    location                       = "northeurope"
    infrastructure_subnet_id       = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-products-dev/providers/Microsoft.Network/virtualNetworks/vnet-ecommercestore-products-dev/subnets/snet-aca"
    internal_load_balancer_enabled = false
    public_network_access          = "Enabled"
  }
}
override_resource {
  target          = azapi_resource.documentdb
  override_during = apply
  values = {
    id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-users-dev/providers/Microsoft.DocumentDB/mongoClusters/docdb-ecusers-dev-demo01"
    output = { properties = {
      administrator    = { userName = "azure-assigned-admin" }
      compute          = { tier = "Free" }
      storage          = { sizeGb = 32 }
      highAvailability = { targetMode = "Disabled" }
    } }
  }
}
override_data {
  target          = data.azapi_resource_action.connection_strings
  override_during = apply
  values = { output = { connectionStrings = [
    { connectionString = "mongodb+srv://<user>:<password>@actual-service-endpoint.example/?discard=old-options" }
  ] } }
}
override_resource {
  target          = azurerm_resource_group.users
  override_during = apply
  values          = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-users-dev" }
}
override_resource {
  target          = azurerm_user_assigned_identity.users
  override_during = apply
  values = {
    id           = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-users-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-ecommercestore-users-dev"
    principal_id = "22222222-2222-2222-2222-222222222222"
  }
}
override_resource {
  target          = azurerm_key_vault.users
  override_during = apply
  values          = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-users-dev/providers/Microsoft.KeyVault/vaults/kv-ecu-dev-demo01" }
}
override_resource {
  target          = azurerm_key_vault_secret.users_mongo
  override_during = apply
  values          = { versionless_id = "https://kv-ecu-dev-demo01.vault.azure.net/secrets/users-mongo-connection" }
}
variables {
  subscription_id                = "11111111-1111-1111-1111-111111111111"
  operator_object_id             = "33333333-3333-3333-3333-333333333333"
  name_suffix                    = "demo01"
  mongo_admin_password           = "Example space+&Passw0rd!"
  environment                    = "dev"
  documentdb_location            = "northeurope"
  deploy_users_app               = false
  users_image                    = null
  users_deployment_stage         = "prepare"
  users_mongo_egress_ipv4        = {}
  users_external_ingress_enabled = false
  api_operator_ipv4              = null
  min_replicas                   = 0
}

# Every provider is mocked; this resolves dynamic AzAPI results without contacting Azure.
run "assigned_credentials_reach_key_vault" {
  command = apply
  assert {
    condition     = azurerm_key_vault_secret.users_mongo.value == "mongodb+srv://azure-assigned-admin:Example%20space%2B%26Passw0rd%21@actual-service-endpoint.example/?tls=true&authMechanism=SCRAM-SHA-256&retrywrites=false&maxIdleTimeMS=120000&serverSelectionTimeoutMS=3000&connectTimeoutMS=3000"
    error_message = "Use assigned username, actual service SRV endpoint, URI-escaped credentials, TLS and disabled retryable writes."
  }
}
