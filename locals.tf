locals {
  names = {
    resource_group = "rg-ecommercestore-users-${var.environment}"
    app            = "ca-ecommercestore-users-${var.environment}"
    identity       = "id-ecommercestore-users-${var.environment}"
    key_vault      = "kv-ecu-${var.environment}-${var.name_suffix}"
    documentdb     = "docdb-ecusers-${var.environment}-${var.name_suffix}"
  }
  shared_environment = var.shared_environment == null ? {
    name                = "cae-ecommercestore-products-${var.environment}"
    resource_group_name = "rg-ecommercestore-products-${var.environment}"
  } : var.shared_environment
  serving = var.users_deployment_stage == "serve"
  tags = {
    application = "EcommerceStore"
    component   = "Users"
    environment = var.environment
    managed_by  = "Terraform"
    purpose     = "portfolio"
  }
  mongo_database_name = "ecommerce-store-users-db"
  # The service, not a guessed cluster-name hostname, supplies the SRV endpoint.
  mongo_templates = [for entry in data.azapi_resource_action.connection_strings.output.connectionStrings :
    entry.connectionString if can(regex("^mongodb\\+srv://<user>:<password>@", entry.connectionString))
  ]
  mongo_template    = try(local.mongo_templates[0], "")
  mongo_username    = azapi_resource.documentdb.output.properties.administrator.userName
  mongo_credentials = "${replace(urlencode(local.mongo_username), "+", "%20")}:${replace(urlencode(var.mongo_admin_password), "+", "%20")}"
  mongo_uri_base    = trimsuffix(split("?", replace(local.mongo_template, "<user>:<password>", local.mongo_credentials))[0], "/")
  mongo_connection  = "${local.mongo_uri_base}/?tls=true&authMechanism=SCRAM-SHA-256&retrywrites=false&maxIdleTimeMS=120000&serverSelectionTimeoutMS=3000&connectTimeoutMS=3000"
  container_environment = {
    ASPNETCORE_ENVIRONMENT                          = "Production"
    ASPNETCORE_HTTP_PORTS                           = "8080"
    MongoDbSettings__InitializeOnStartup            = tostring(local.serving)
    MongoDbSettings__DatabaseName                   = local.mongo_database_name
    MongoDbSettings__CustomerCollectionName         = "customers"
    MongoDbSettings__CustomersHistoryCollectionName = "customers-history"
    MongoDbSettings__AdminCollectionName            = "admins"
    MongoDbSettings__AdminsHistoryCollectionName    = "admins-history"
    MongoDbSettings__FavoriteCollectionName         = "favorites"
  }
}
