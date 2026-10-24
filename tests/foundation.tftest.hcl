mock_provider "azurerm" { override_during = plan }
mock_provider "azapi" { override_during = plan }

override_data {
  target          = data.azurerm_client_config.current
  override_during = plan
  values          = { tenant_id = "11111111-1111-1111-1111-111111111111" }
}
override_data {
  target          = data.azurerm_container_app_environment.shared
  override_during = plan
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
  override_during = plan
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
  override_during = plan
  values = { output = { connectionStrings = [
    { connectionString = "mongodb+srv://<user>:<password>@actual-service-endpoint.example/?discard=old-options" }
  ] } }
}
override_resource {
  target          = azurerm_resource_group.users
  override_during = plan
  values          = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-users-dev" }
}
override_resource {
  target          = azurerm_user_assigned_identity.users
  override_during = plan
  values = {
    id           = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-users-dev/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-ecommercestore-users-dev"
    principal_id = "22222222-2222-2222-2222-222222222222"
  }
}
override_resource {
  target          = azurerm_key_vault.users
  override_during = plan
  values          = { id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-ecommercestore-users-dev/providers/Microsoft.KeyVault/vaults/kv-ecu-dev-demo01" }
}
override_resource {
  target          = azurerm_key_vault_secret.users_mongo
  override_during = plan
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

run "free_foundation" {
  command = plan
  assert {
    condition = (
      azurerm_resource_group.users.name == "rg-ecommercestore-users-dev" &&
      azurerm_resource_group.users.location == "northeurope" &&
      azapi_resource.documentdb.body.properties.compute.tier == "Free" &&
      azapi_resource.documentdb.body.properties.storage.sizeGb == 32 &&
      azapi_resource.documentdb.body.properties.highAvailability.targetMode == "Disabled" &&
      azapi_resource.documentdb.body.properties.sharding.shardCount == 1 &&
      azapi_resource.documentdb.body.properties.authConfig.allowedModes == ["NativeAuth"] &&
      length(azurerm_container_app.users) == 0 && length(azapi_resource.users_egress) == 0
    )
    error_message = "Foundation must be Free/32 GB, native auth, single shard, no HA or app/firewall bootstrap."
  }
  assert {
    condition = (
      azurerm_key_vault.users.rbac_authorization_enabled &&
      azurerm_role_assignment.users_secrets.principal_id == azurerm_user_assigned_identity.users.principal_id &&
      azurerm_role_assignment.users_secrets.role_definition_name == "Key Vault Secrets User" &&
      azurerm_role_assignment.operator_secrets.principal_id == var.operator_object_id &&
      azurerm_role_assignment.operator_secrets.role_definition_name == "Key Vault Secrets Officer" &&
      azurerm_role_assignment.users_secrets.scope == azurerm_key_vault.users.id
    )
    error_message = "The app uses its own identity to read its own Key Vault; operator RBAC is explicit."
  }
  assert {
    condition     = local.mongo_connection == "mongodb+srv://azure-assigned-admin:Example%20space%2B%26Passw0rd%21@actual-service-endpoint.example/?tls=true&authMechanism=SCRAM-SHA-256&retrywrites=false&maxIdleTimeMS=120000&serverSelectionTimeoutMS=3000&connectTimeoutMS=3000"
    error_message = "Use assigned username, actual service SRV endpoint, URI-escaped credentials, TLS and disabled retryable writes."
  }
}

run "prepare_without_mongo_access" {
  command = plan
  variables {
    deploy_users_app = true
    users_image      = "mb0101/ecommerce-store-users-api@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }
  assert {
    condition = (
      azurerm_container_app.users[0].container_app_environment_id == data.azurerm_container_app_environment.shared.id &&
      !azurerm_container_app.users[0].ingress[0].external_enabled &&
      azurerm_container_app.users[0].ingress[0].target_port == 8080 &&
      azurerm_container_app.users[0].workload_profile_name == "Consumption" &&
      azurerm_container_app.users[0].template[0].min_replicas == 0 &&
      azurerm_container_app.users[0].template[0].max_replicas == 1 &&
      azurerm_container_app.users[0].template[0].container[0].cpu == 0.25 &&
      azurerm_container_app.users[0].template[0].container[0].memory == "0.5Gi" &&
      azurerm_container_app.users[0].template[0].container[0].readiness_probe[0].path == "/health/live" &&
      one([for item in azurerm_container_app.users[0].template[0].container[0].env : item.value if item.name == "MongoDbSettings__InitializeOnStartup"]) == "false"
    )
    error_message = "Prepare reuses the environment, remains internal and small, and skips Mongo startup."
  }
}

run "serve_with_exact_egress" {
  command = plan
  variables {
    deploy_users_app        = true
    users_image             = "mb0101/ecommerce-store-users-api@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    users_deployment_stage  = "serve"
    users_mongo_egress_ipv4 = { ip-203-0-113-4 = "203.0.113.4", ip-203-0-113-5 = "203.0.113.5" }
  }
  assert {
    condition = (
      length(azapi_resource.users_egress) == 2 &&
      azapi_resource.users_egress["ip-203-0-113-4"].body.properties.startIpAddress == "203.0.113.4" &&
      azapi_resource.users_egress["ip-203-0-113-4"].body.properties.endIpAddress == "203.0.113.4" &&
      azurerm_container_app.users[0].template[0].container[0].readiness_probe[0].path == "/health/ready" &&
      azurerm_container_app.users[0].template[0].container[0].liveness_probe[0].path == "/health/live" &&
      one([for item in azurerm_container_app.users[0].template[0].container[0].env : item.value if item.name == "MongoDbSettings__InitializeOnStartup"]) == "true" &&
      one([for item in azurerm_container_app.users[0].template[0].container[0].env : item.secret_name if item.name == "MongoDbSettings__ConnectionString"]) == "users-mongo-connection" &&
      one(azurerm_container_app.users[0].secret).key_vault_secret_id == azurerm_key_vault_secret.users_mongo.versionless_id
    )
    error_message = "Serve enables initialization and DB readiness after exact firewall rules, using a Key Vault reference."
  }
}

run "operator_only_swagger" {
  command = plan
  variables {
    deploy_users_app               = true
    users_image                    = "mb0101/ecommerce-store-users-api@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    users_deployment_stage         = "serve"
    users_mongo_egress_ipv4        = { ip-203-0-113-4 = "203.0.113.4" }
    users_external_ingress_enabled = true
    api_operator_ipv4              = "198.51.100.9"
  }
  assert {
    condition = (
      azurerm_container_app.users[0].ingress[0].external_enabled &&
      one(azurerm_container_app.users[0].ingress[0].ip_security_restriction).ip_address_range == "198.51.100.9/32" &&
      length(azapi_resource.users_egress) == 1 &&
      azapi_resource.users_egress["ip-203-0-113-4"].body.properties.startIpAddress == "203.0.113.4"
    )
    error_message = "API operator access must not open a MongoDB operator firewall rule."
  }
}
