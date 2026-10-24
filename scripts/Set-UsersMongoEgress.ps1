#Requires -Version 7.2
[CmdletBinding()]
param(
    [string]$TerraformPath = 'terraform',
    [string]$InputsPath = (Join-Path $PSScriptRoot '..' 'users-deployment.tfvars.json')
)
. (Join-Path $PSScriptRoot 'UsersDeployment.Common.ps1')
if (-not (Test-Path -LiteralPath $InputsPath)) { throw 'Create and apply the explicit Users deployment inputs first.' }
$inputs = Read-UsersInputs -Path $InputsPath
$foundation = Get-UsersTerraformOutput -TerraformPath $TerraformPath -Name 'users_foundation'
$deployment = Get-UsersTerraformOutput -TerraformPath $TerraformPath -Name 'users_deployment'
if (-not $deployment.enabled -or -not $inputs.deploy_users_app) { throw 'Apply the Users preparation app first.' }
# Read the current app, not a stale state output or another service's addresses.
$raw = & az containerapp show --subscription $foundation.subscription_id `
    --resource-group $deployment.resource_group_name --name $deployment.name `
    --query '{state:properties.provisioningState,addresses:properties.outboundIpAddresses}' --output json
if ($LASTEXITCODE -ne 0) { throw 'Users outbound address lookup failed; inputs were not changed.' }
$observed = ($raw -join "`n") | ConvertFrom-Json
if ($observed.state -ne 'Succeeded') { throw 'Users provisioning has not succeeded; inputs were not changed.' }
$addresses = @($observed.addresses | Sort-Object -Unique)
if ($addresses.Count -eq 0) { throw 'Azure returned no outbound IPv4 addresses; inputs were not changed.' }
$rules = [ordered]@{}
foreach ($address in $addresses) {
    if (-not (Test-UsersPublicIpv4 $address)) { throw "Azure returned an invalid outbound IPv4 address: $address. Inputs were not changed." }
    $rules["ip-$($address.Replace('.', '-'))"] = $address
}
$inputs.users_mongo_egress_ipv4 = $rules
Write-UsersInputs -Inputs $inputs -Path $InputsPath
Write-Host "Recorded $($rules.Count) exact Users egress addresses in $InputsPath. No firewall rules have been applied."
