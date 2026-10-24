# EcommerceStore Users infrastructure

Deploy the ASP.NET 10 Users API into the **existing Products ACA environment and delegated network**, with an **Azure DocumentDB Free Tier** MongoDB-compatible cluster. This root never creates, imports, changes or destroys the Products/BFF environment, VNet or subnet. Deploy Users after Products; destroy Users and BFF before the Products foundation.

Azure DocumentDB is the new name of **Azure Cosmos DB for MongoDB vCore**. This is not the RU-based Cosmos DB MongoDB API. Its resource type still uses `Microsoft.DocumentDB/mongoClusters`.

## What this root owns

| Resource | Development name / configuration |
| --- | --- |
| Resource group | `rg-ecommercestore-users-dev` |
| Container App | `ca-ecommercestore-users-dev`, enabled explicitly after foundation |
| Shared environment (read only) | `cae-ecommercestore-products-dev` in `rg-ecommercestore-products-dev` |
| Managed identity | `id-ecommercestore-users-dev` |
| Key Vault | `kv-ecu-dev-<name_suffix>`; `users-mongo-connection` secret |
| DocumentDB cluster | `docdb-ecusers-dev-<name_suffix>`; Free, 32 GB, one shard, no HA |
| Logical database | `ecommerce-store-users-db`, created by the app's collection/index initializer |
| Remote state | existing `stecomtfstatemb261011/tfstate`, **`users/development.terraform.tfstate`** |

The app uses a quarter vCPU / 0.5 GiB, Consumption, one revision and zero to one replicas. Internal HTTPS ingress is the default. There is no new environment, VNet, subnet, NAT gateway, private endpoint, ACR, paid MongoDB fallback or Log Analytics workspace. Existing shared logging/network settings continue to apply.

The Users repo has no dependency on Products SQL, photo storage, Redis or a message broker for this deployment. BFF route configuration, Angular integration and Entra application authentication are separate follow-ups. Do not expose this currently unauthenticated Users API broadly.

## Service choice and costs

[DocumentDB Free Tier](https://learn.microsoft.com/en-us/azure/documentdb/free-tier) provides 32 GB, supports **North Europe**, and allows **one free cluster per subscription**. It has no HA, Entra database authentication, backup/restore or diagnostic logging, and pauses after 60 days of inactivity. There is no automatic paid fallback: if the free quota/region is unavailable, stop and review the error. Never change `Free` to `M10` to get an apply through; M10 is paid. Review [current pricing](https://azure.microsoft.com/en-us/pricing/details/documentdb/) before any upgrade. This disposable portfolio database is not a backup strategy.

ACA executions/requests, Key Vault operations, logging and traffic can still incur usage charges. Scaling Users to zero does not remove shared environment/network charges or costs of other apps. Keep `min_replicas=0`; delete the stack when the portfolio exercise is complete. Free database compute does not mean the whole deployment is free.

Free Tier preassigns its admin username. AzAPI reads the returned username and the service's `listConnectionStrings` SRV template; it never constructs a hostname from the cluster name. Password-only creation is modeled using the stable `2026-06-01` ARM API. A password hash versions the write-only update, so changing the password updates both the cluster and Key Vault. The state still contains the Key Vault secret value: protect the existing state account and never publish state, tfvars, plans or logs containing secrets.

Native MongoDB authentication is required on Free Tier. The managed identity grants **Key Vault Secrets User**, not passwordless database access. The human running Terraform must match `operator_object_id` and receives **Key Vault Secrets Officer**. Use a strong unique disposable database administrator password; a restricted application database user is future hardening, not claimed here.

## Required application change

First merge [Users PR #130](https://github.com/MichalBoczula/ECommerceStoreUsers/pull/130) after its checks pass. The normal master workflow then publishes a scanned Docker Hub image. Record that **new image's immutable digest**. The September 28 image predates this change and cannot perform this staged rollout correctly.

The companion change preserves normal MongoDB startup/index initialization by default. It adds `MongoDbSettings__InitializeOnStartup=false` for the internal preparation revision, and accepts the `isdbgrid` gateway topology in readiness while still requiring writable session support and an application-database ping. These are MongoDB indexes/collections, not EF SQL migrations.

The service uses cross-collection current/history transactions. Existing native MongoDB integration/rollback tests remain required. Mock Terraform tests and a green health probe do **not** prove full Azure DocumentDB transaction compatibility. Complete a real customer/admin create/update, conflict, history and rollback check against the deployed cluster before treating the deployment as verified.

## 1. Initialize a PowerShell 7 session

Run from this repository. Prerequisites: Terraform **1.16.5**, Azure CLI, an Azure login with resource creation plus role-assignment rights, the existing state account/container, and the Products foundation already deployed. This workflow runs locally as the human operator; CI below has no Azure credentials.

```powershell
Set-Location D:\Programowanie\Apps\ECommerceStoreUsers.Terraform
$ErrorActionPreference = 'Stop'
$usersTerraform = Join-Path $env:LOCALAPPDATA 'Programs\Terraform\1.16.5\terraform.exe'
if (-not (Test-Path -LiteralPath $usersTerraform)) { throw 'Terraform 1.16.5 was not found; set $usersTerraform to its full path' }
& $usersTerraform version
if ($LASTEXITCODE -ne 0) { throw 'Terraform version check failed' }
az login
if ($LASTEXITCODE -ne 0) { throw 'Azure login failed' }
$usersSubscriptionId = Read-Host 'Portfolio subscription UUID'
az account set --subscription $usersSubscriptionId
if ($LASTEXITCODE -ne 0) { throw 'Subscription selection failed' }
az account show --query '{subscription:id,tenant:tenantId,name:name}' --output json
if ($LASTEXITCODE -ne 0) { throw 'Account verification failed' }
az ad signed-in-user show --query id --output tsv
if ($LASTEXITCODE -ne 0) { throw 'Operator object ID lookup failed' }
```

Copy examples **only when the destination does not exist**. Do not overwrite real inputs during later sessions.

```powershell
if (-not (Test-Path .\terraform.tfvars)) { Copy-Item .\terraform.tfvars.example .\terraform.tfvars }
if (-not (Test-Path .\backend.hcl)) { Copy-Item .\backend.hcl.example .\backend.hcl }
if (-not (Test-Path .\users-deployment.tfvars.json)) {
    Copy-Item .\users-deployment.tfvars.json.example .\users-deployment.tfvars.json
}
```

Edit `terraform.tfvars`: set subscription UUID, the signed-in operator's **Entra object UUID** (not client ID), and a unique `name_suffix` such as `mb261024`. Check `backend.hcl` still names `stecomtfstatemb261011`, `tfstate`, and **`users/development.terraform.tfstate`**. Keep the Products, BFF and Users state keys separate. The backend account itself is not managed by this root.

Use **one explicit deployment file**. `users-deployment.tfvars.json` is intentionally not auto-loaded; pass it to every plan and destroy. Do not create `*.auto.tfvars*` files or put rollout settings in `terraform.tfvars`, because they can silently override your intended stage or contaminate tests. All configuration inputs used by tests have explicit test baselines.

```powershell
$usersPassword = Read-Host 'Strong DocumentDB admin password; reuse on subsequent plans' -AsSecureString
$env:TF_VAR_mongo_admin_password = ConvertFrom-SecureString $usersPassword -AsPlainText
Remove-Variable usersPassword
az provider register --namespace Microsoft.DocumentDB --wait
if ($LASTEXITCODE -ne 0) { throw 'DocumentDB provider registration failed' }
& $usersTerraform init '-backend-config=backend.hcl'
if ($LASTEXITCODE -ne 0) { throw 'Initialization failed' }
& $usersTerraform fmt '-check' '-recursive'
if ($LASTEXITCODE -ne 0) { throw 'Formatting failed' }
& $usersTerraform validate
if ($LASTEXITCODE -ne 0) { throw 'Validation failed' }
& $usersTerraform test
if ($LASTEXITCODE -ne 0) { throw 'Mocked tests failed' }
pwsh -NoProfile -File .\tests\Test-UsersDeployment.ps1
if ($LASTEXITCODE -ne 0) { throw 'Offline script checks failed' }
```

If init reports a changed backend, inspect the configured account/container/key first. Use `-reconfigure` only when reconnecting to this same intended Users backend. Do not migrate Products state to Users or delete a remote state blob to fix an initialization error. A new terminal needs `$usersTerraform`, the Azure login and the same password again.

## 2. Apply the foundation

The helper edits local inputs only. Plan, review, and apply are deliberately separate. A foundation rerun refuses to disable an already enabled app.

```powershell
.\scripts\Set-UsersDeployment.ps1 -Stage Foundation
& $usersTerraform plan '-input=false' '-var-file=users-deployment.tfvars.json' '-out=users-foundation.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Foundation planning failed' }
```

Review: a Users RG, Free/32 GB cluster, identity, vault, two vault role assignments and one secret. No shared-resource replacement or paid database SKU. Then:

```powershell
& $usersTerraform apply users-foundation.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Foundation apply failed; retain state and inspect the error' }
& $usersTerraform output -json users_foundation
if ($LASTEXITCODE -ne 0) { throw 'Foundation output lookup failed' }
```

Azure creation, Free Tier's assigned username, real SRV DNS and service compatibility still require this manual Azure run. The checks here do not provision a real cluster.

## 3. Prepare the real Users image

Use the immutable digest published after Users PR #130 merges, for example the `mb0101/ecommerce-store-users-api@sha256:...` reference shown by that successful master workflow. Foundation can be applied before that image is available.

```powershell
$usersImage = Read-Host 'New compatible Users image, including @sha256:digest'
.\scripts\Set-UsersDeployment.ps1 -Stage Prepare -Image $usersImage
& $usersTerraform plan '-input=false' '-var-file=users-deployment.tfvars.json' '-out=users-prepare.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Prepare planning failed' }
```

Review an internal Users Container App in the existing Products environment, with `MongoDbSettings__InitializeOnStartup=false` and readiness/liveness at `/health/live`. The database is not expected to be reachable yet. Apply separately:

```powershell
& $usersTerraform apply users-prepare.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Prepare apply failed; retain state' }
```

## 4. Record exact egress, then serve

```powershell
.\scripts\Set-UsersMongoEgress.ps1 -TerraformPath $usersTerraform
Get-Content .\users-deployment.tfvars.json
.\scripts\Set-UsersDeployment.ps1 -Stage Serve
& $usersTerraform plan '-input=false' '-var-file=users-deployment.tfvars.json' '-out=users-serve.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Serve planning failed' }
```

The egress helper reads the applied Users names from Terraform and **queries that app's current Azure outbound IPs**, sorts/deduplicates them, and merges stable `ip-<IPv4-with-dashes>` keys into the same ignored deployment file. It preserves image, stage and other settings, and leaves the file unchanged on lookup/validation failure. It never applies firewall changes itself. Do not copy Products outbound addresses merely because the environment is shared.

Review one exact start=end firewall rule per unique address, followed by a Users revision with initialization `true` and readiness `/health/ready`. There is no `0.0.0.0`, broad range, operator database rule or apply-time `for_each`. Then:

```powershell
& $usersTerraform apply users-serve.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Serve apply failed; retain state and inspect the error' }
$usersDeployment = (& $usersTerraform output -json users_deployment) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Deployment output lookup failed' }
$usersDeployment = $usersDeployment | ConvertFrom-Json
az containerapp show --resource-group $usersDeployment.resource_group_name --name $usersDeployment.name `
    --query "{state:properties.provisioningState,ready:properties.latestReadyRevisionName,stage:properties.template.containers[0].env[?name=='MongoDbSettings__InitializeOnStartup'].value}" --output json
if ($LASTEXITCODE -ne 0) { throw 'Users runtime verification failed' }
az containerapp logs show --resource-group $usersDeployment.resource_group_name --name $usersDeployment.name `
    --type system --tail 50 --format json
if ($LASTEXITCODE -ne 0) { throw 'System logs failed' }
az containerapp logs show --resource-group $usersDeployment.resource_group_name --name $usersDeployment.name `
    --type console --container users --tail 100 --format text
if ($LASTEXITCODE -ne 0) { throw 'Console logs failed' }
```

Keep initialization **true** for normal serving; this is idempotent MongoDB index setup, unlike the one-off Products SQL bootstrap flag. No console replica at idle is normal when min replicas is zero. System logs require JSON format. Internal URLs work from the shared ACA environment, not your local browser; an external Azure 404 does not prove the process is stopped.

If Azure changes egress later, rerun the helper, review the exact firewall diff, and apply a fresh plan with the same explicit input file. Do not return an existing serving app to prepare just to update an image. `Set-UsersDeployment.ps1 -Stage Serve -Image <new-digest>` preserves its firewall settings.

## 5. Optional attended Swagger verification

Prefer calls through the BFF once its Users routes are configured. For a temporary local check, restrict the unauthenticated Users API to your current public IPv4; this does not grant that address MongoDB access. Keep the IP only in ignored local inputs.

```powershell
$usersOperatorIpv4 = Read-Host 'Current public IPv4 for temporary API access'
.\scripts\Set-UsersDeployment.ps1 -Stage Swagger -ApiOperatorIpv4 $usersOperatorIpv4
& $usersTerraform plan '-input=false' '-var-file=users-deployment.tfvars.json' '-out=users-swagger.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Swagger planning failed' }
```

Review and apply separately:

```powershell
& $usersTerraform apply users-swagger.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Swagger apply failed' }
$usersDeploymentJson = (& $usersTerraform output -json users_deployment) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Deployment output lookup failed' }
$usersDeployment = $usersDeploymentJson | ConvertFrom-Json
Invoke-WebRequest "$($usersDeployment.base_url)/health/ready" -TimeoutSec 30
Write-Host "$($usersDeployment.base_url)/swagger/index.html"
```

Allow for ACA cold start. Verify `/health/live` and `/health/ready`, Swagger, and actual disposable customer/admin/favorite operations using the current OpenAPI request schemas. Verify transactional current/history consistency and rollback on Azure before marking the database integration complete; native MongoDB CI alone cannot establish that. Do not use real customer information in this portfolio environment.

After testing, clear personal API access and retain serving/database settings:

```powershell
.\scripts\Set-UsersDeployment.ps1 -Stage Internal
& $usersTerraform plan '-input=false' '-var-file=users-deployment.tfvars.json' '-out=users-internal.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Internal planning failed' }
```

Review, then apply `users-internal.tfplan` separately and check `$LASTEXITCODE`. This restores internal ingress, clears `api_operator_ipv4` and sets minimum replicas to zero. It does not delete the app, close its required database rules or disable index initialization.

## 6. Destroy Users only

Keep the backend, state, password and explicit deployment file. The destroy plan includes the Users database and its data; inspect it before applying. Products, BFF and the state account must not appear as managed deletions.

```powershell
& $usersTerraform plan '-destroy' '-input=false' '-var-file=users-deployment.tfvars.json' '-out=users-destroy.tfplan'
if ($LASTEXITCODE -ne 0) { throw 'Destroy planning failed; no resources were deleted' }
```

Apply the reviewed plan separately:

```powershell
& $usersTerraform apply users-destroy.tfplan
if ($LASTEXITCODE -ne 0) { throw 'Destroy incomplete; retain state and inputs and inspect Azure before retrying' }
& $usersTerraform state list
if ($LASTEXITCODE -ne 0) { throw 'State verification failed' }
Remove-Item Env:\TF_VAR_mongo_admin_password
```

If Azure reports a delete polling error, verify the specific Users resource status, then create and review a **new** destroy plan. Do not delete state, blindly remove state entries, delete the shared ACA environment/VNet, or reuse a stale saved plan. Key Vault soft deletion lasts seven days; the provider attempts purge on destroy and needs the corresponding permission. A failed purge needs review before reusing the vault name.

## Checks without Azure

Pinned tools/providers: Terraform 1.16.5, AzureRM 5.9.0, AzAPI 2.13.0. The lock file includes signed Linux and Windows package checksums. CI runs backend-disabled init, fmt, schema validation, 21 mocked plans, and the offline PowerShell deployment/egress checks on Linux and Windows. It has no Azure credentials and never applies resources.

Tests cover shared environment reuse, zero-cost database SKU parameters, encoded service-assigned credentials, exact plan-known firewall maps, internal prepare vs database-ready serve, Key Vault references and isolated operator-only Swagger access. The PowerShell checks cover merging/deduplication, stable reruns, input preservation on failure, private/Azure-wide rejection and retaining serving settings when closing Swagger.

ARM references: [mongoClusters 2026-06-01](https://learn.microsoft.com/en-us/azure/templates/microsoft.documentdb/2026-06-01/mongoclusters), [Microsoft API specification](https://github.com/Azure/azure-rest-api-specs/tree/main/specification/mongocluster/resource-manager/Microsoft.DocumentDB/MongoCluster/stable/2026-06-01), [DocumentDB transactions](https://learn.microsoft.com/en-us/azure/documentdb/how-to-transactions).
