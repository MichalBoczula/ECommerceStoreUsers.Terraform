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

run "reject_invalid_subscription" {
  command = plan
  variables {
    subscription_id = "bad"
  }
  expect_failures = [var.subscription_id]
}

run "reject_invalid_operator" {
  command = plan
  variables {
    operator_object_id = "bad"
  }
  expect_failures = [var.operator_object_id]
}

run "reject_invalid_environment" {
  command = plan
  variables {
    environment = "Dev-12345"
  }
  expect_failures = [var.environment]
}

run "reject_invalid_suffix" {
  command = plan
  variables {
    name_suffix = "UpperCaseTooLong"
  }
  expect_failures = [var.name_suffix]
}

run "reject_weak_password" {
  command = plan
  variables {
    mongo_admin_password = "short"
  }
  expect_failures = [var.mongo_admin_password]
}

run "reject_paid_region" {
  command = plan
  variables {
    documentdb_location = "westeurope"
  }
  expect_failures = [var.documentdb_location]
}

run "reject_floating_image" {
  command = plan
  variables {
    users_image = "mb0101/ecommerce-store-users-api:latest"
  }
  expect_failures = [var.users_image]
}

run "reject_missing_image" {
  command = plan
  variables {
    deploy_users_app = true
  }
  expect_failures = [var.users_image]
}

run "reject_unknown_stage" {
  command = plan
  variables {
    users_deployment_stage = "production"
  }
  expect_failures = [var.users_deployment_stage]
}

run "reject_serve_without_egress" {
  command = plan
  variables {
    deploy_users_app       = true
    users_image            = "mb0101/ecommerce-store-users-api@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    users_deployment_stage = "serve"
  }
  expect_failures = [var.users_deployment_stage]
}

run "reject_azure_wide_firewall" {
  command = plan
  variables {
    users_mongo_egress_ipv4 = { all = "0.0.0.0" }
  }
  expect_failures = [var.users_mongo_egress_ipv4]
}

run "reject_private_firewall" {
  command = plan
  variables {
    users_mongo_egress_ipv4 = { private = "10.1.2.3" }
  }
  expect_failures = [var.users_mongo_egress_ipv4]
}

run "reject_range_firewall" {
  command = plan
  variables {
    users_mongo_egress_ipv4 = { range = "203.0.113.4/24" }
  }
  expect_failures = [var.users_mongo_egress_ipv4]
}

run "reject_invalid_firewall" {
  command = plan
  variables {
    users_mongo_egress_ipv4 = { invalid = "999.1.1.1" }
  }
  expect_failures = [var.users_mongo_egress_ipv4]
}

run "reject_external_without_operator" {
  command = plan
  variables {
    users_external_ingress_enabled = true
  }
  expect_failures = [var.users_external_ingress_enabled]
}

run "reject_invalid_api_operator" {
  command = plan
  variables {
    api_operator_ipv4 = "192.168.1.3"
  }
  expect_failures = [var.api_operator_ipv4]
}

run "reject_paid_scale" {
  command = plan
  variables {
    min_replicas = 2
  }
  expect_failures = [var.min_replicas]
}
