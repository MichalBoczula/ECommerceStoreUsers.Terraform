variable "subscription_id" {
  type        = string
  description = "Azure subscription UUID; keep identical to the selected Azure CLI subscription."
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a UUID."
  }
}

variable "operator_object_id" {
  type        = string
  description = "Human operator Entra object UUID for managing this stack's Key Vault secret."
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.operator_object_id))
    error_message = "operator_object_id must be a UUID."
  }
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Lowercase environment suffix, at most eight characters."
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,7}$", var.environment))
    error_message = "environment must start with a lowercase letter and contain at most eight lowercase letters or digits."
  }
}

variable "name_suffix" {
  type        = string
  description = "Globally unique lowercase suffix, three to eight letters/digits (for example mb261024)."
  validation {
    condition     = can(regex("^[a-z0-9]{3,8}$", var.name_suffix))
    error_message = "name_suffix must contain three to eight lowercase letters/digits."
  }
}

variable "mongo_admin_password" {
  type        = string
  sensitive   = true
  description = "DocumentDB native admin password. Free Tier assigns the username. Stored in the protected Terraform state and Key Vault."
  validation {
    condition = (
      length(var.mongo_admin_password) >= 16 && length(var.mongo_admin_password) <= 128 &&
      can(regex("[A-Z]", var.mongo_admin_password)) && can(regex("[a-z]", var.mongo_admin_password)) &&
      can(regex("[0-9]", var.mongo_admin_password)) && can(regex("[^a-zA-Z0-9]", var.mongo_admin_password))
    )
    error_message = "Use a 16–128 character password with uppercase, lowercase, a digit and a symbol."
  }
}

variable "shared_environment" {
  type = object({
    name                = string
    resource_group_name = string
  })
  default     = null
  description = "Read-only reference to Products' existing ACA environment; null derives names from environment."
}

variable "documentdb_location" {
  type        = string
  default     = "northeurope"
  description = "DocumentDB Free Tier region. North Europe matches the current shared ACA environment. No paid fallback."
  validation {
    condition = contains([
      "brazilsouth", "canadacentral", "centralus", "eastus", "westus", "westus2",
      "francecentral", "germanynorth", "northeurope", "norwayeast", "switzerlandnorth",
      "australiacentral2", "australiaeast", "centralindia", "southindia", "eastasia", "japaneast", "japanwest"
    ], var.documentdb_location)
    error_message = "Select a documented DocumentDB Free Tier region; do not substitute a paid SKU."
  }
}

variable "deploy_users_app" {
  type        = bool
  default     = false
  description = "Create the Users Container App after the foundation and the compatible image are ready."
}

variable "users_image" {
  type        = string
  default     = null
  description = "Public Docker Hub image at an immutable digest, built after the companion DocumentDB startup PR."
  validation {
    condition     = var.users_image == null ? !var.deploy_users_app : can(regex("^mb0101/ecommerce-store-users-api@sha256:[0-9a-f]{64}$", var.users_image))
    error_message = "An enabled app requires mb0101/ecommerce-store-users-api@sha256:<64 lowercase hex characters>."
  }
}

variable "users_deployment_stage" {
  type        = string
  default     = "prepare"
  description = "prepare skips Mongo startup while discovering egress; serve initializes indexes and requires database readiness."
  validation {
    condition     = contains(["prepare", "serve"], var.users_deployment_stage)
    error_message = "users_deployment_stage must be prepare or serve."
  }
  validation {
    condition     = var.users_deployment_stage != "serve" || (var.deploy_users_app && length(var.users_mongo_egress_ipv4) > 0)
    error_message = "serve requires an enabled app and reviewed exact Users outbound IPv4 addresses."
  }
}

variable "users_mongo_egress_ipv4" {
  type        = map(string)
  default     = {}
  description = "Plan-known stable keys and exact IPv4 values observed on the applied Users app, never Products ingress or Azure-wide access."
  validation {
    condition = alltrue([for key, ip in var.users_mongo_egress_ipv4 :
      can(regex("^[a-z][a-z0-9-]{0,39}$", key)) &&
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", ip)) && can(cidrnetmask("${ip}/32")) &&
      !can(regex("^(0\\.|10\\.|127\\.|169\\.254\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.|22[4-9]\\.|23[0-9]\\.|24[0-9]\\.|25[0-5]\\.)", ip))
    ])
    error_message = "Use stable lowercase keys and exact public IPv4 addresses, without CIDRs, ranges, private or Azure-wide 0.0.0.0 rules."
  }
}

variable "users_external_ingress_enabled" {
  type        = bool
  default     = false
  description = "Temporary unauthenticated Swagger access restricted to the separately supplied API operator /32."
  validation {
    condition     = !var.users_external_ingress_enabled || (var.deploy_users_app && var.users_deployment_stage == "serve" && var.api_operator_ipv4 != null)
    error_message = "External testing requires a serving app and api_operator_ipv4. Keep prepare internal."
  }
}

variable "api_operator_ipv4" {
  type        = string
  default     = null
  description = "Current public IPv4 for temporary API testing only; null does not open a database firewall rule."
  validation {
    condition = var.api_operator_ipv4 == null ? true : (
      can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", var.api_operator_ipv4)) &&
      can(cidrnetmask("${var.api_operator_ipv4}/32")) &&
      !can(regex("^(0\\.|10\\.|127\\.|169\\.254\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.|22[4-9]\\.|23[0-9]\\.|24[0-9]\\.|25[0-5]\\.)", var.api_operator_ipv4))
    )
    error_message = "api_operator_ipv4 must be an exact public IPv4 address."
  }
}

variable "min_replicas" {
  type        = number
  default     = 0
  description = "Zero for idle scale-to-zero; one only during an attended test."
  validation {
    condition     = contains([0, 1], var.min_replicas)
    error_message = "min_replicas must be zero or one; max_replicas is fixed at one."
  }
}
