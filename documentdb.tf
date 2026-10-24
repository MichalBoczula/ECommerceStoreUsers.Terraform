# Azure DocumentDB is the renamed Cosmos DB for MongoDB vCore service.
# AzAPI supports Free Tier's server-assigned username without a fake configured login.
resource "azapi_resource" "documentdb" {
  type      = "Microsoft.DocumentDB/mongoClusters@2026-06-01"
  name      = local.names.documentdb
  parent_id = azurerm_resource_group.users.id
  location  = var.documentdb_location
  tags      = local.tags
  body = {
    properties = {
      createMode          = "Default"
      serverVersion       = "8.0"
      publicNetworkAccess = "Enabled"
      compute             = { tier = "Free" }
      storage             = { sizeGb = 32, type = "PremiumSSD" }
      sharding            = { shardCount = 1 }
      highAvailability    = { targetMode = "Disabled" }
      authConfig          = { allowedModes = ["NativeAuth"] }
    }
  }
  sensitive_body = {
    properties = {
      administrator = { password = var.mongo_admin_password }
    }
  }
  sensitive_body_version = {
    "properties.administrator.password" = sha256(var.mongo_admin_password)
  }
  response_export_values = [
    "properties.administrator.userName", "properties.compute.tier",
    "properties.storage.sizeGb", "properties.highAvailability.targetMode"
  ]
  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
  lifecycle {
    postcondition {
      condition = (
        self.output.properties.compute.tier == "Free" &&
        self.output.properties.storage.sizeGb == 32 &&
        self.output.properties.highAvailability.targetMode == "Disabled"
      )
      error_message = "Expected Free Tier, 32 GB and disabled HA. Review Azure; this stack never chooses a paid fallback."
    }
  }
}

data "azapi_resource_action" "connection_strings" {
  type                   = "Microsoft.DocumentDB/mongoClusters@2026-06-01"
  resource_id            = azapi_resource.documentdb.id
  action                 = "listConnectionStrings"
  method                 = "POST"
  response_export_values = ["connectionStrings"]
}

# Terraform can plan these instance keys before apply; every rule allows exactly one observed address.
resource "azapi_resource" "users_egress" {
  for_each  = var.users_mongo_egress_ipv4
  type      = "Microsoft.DocumentDB/mongoClusters/firewallRules@2026-06-01"
  name      = "aca-${each.key}"
  parent_id = azapi_resource.documentdb.id
  body = {
    properties = {
      startIpAddress = each.value
      endIpAddress   = each.value
    }
  }
}
