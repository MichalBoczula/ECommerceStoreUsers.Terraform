#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('Foundation', 'Prepare', 'Serve', 'Swagger', 'Internal')][string]$Stage,
    [string]$Image,
    [string]$ApiOperatorIpv4,
    [string]$InputsPath = (Join-Path $PSScriptRoot '..' 'users-deployment.tfvars.json')
)
. (Join-Path $PSScriptRoot 'UsersDeployment.Common.ps1')
$inputs = Read-UsersInputs -Path $InputsPath
switch ($Stage) {
    'Foundation' {
        if ($inputs.deploy_users_app) { throw 'Foundation would remove an existing app. Retain the current deployment inputs.' }
    }
    'Prepare' {
        if ($inputs.users_deployment_stage -eq 'serve') { throw 'A serving app must not return to preparation. Update its immutable image while retaining serve.' }
        if ($Image -notmatch '^mb0101/ecommerce-store-users-api@sha256:[0-9a-f]{64}$') { throw 'Prepare requires the new compatible immutable Users image.' }
        $inputs.deploy_users_app = $true
        $inputs.users_image = $Image
        $inputs.users_deployment_stage = 'prepare'
        $inputs.users_external_ingress_enabled = $false
        $inputs.api_operator_ipv4 = $null
    }
    'Serve' {
        if (-not $inputs.deploy_users_app -or $inputs.users_mongo_egress_ipv4.Count -eq 0) { throw 'Apply prepare and record exact Users egress before serve.' }
        foreach ($address in $inputs.users_mongo_egress_ipv4.Values) {
            if (-not (Test-UsersPublicIpv4 $address)) { throw 'Invalid Users database egress address.' }
        }
        $inputs.users_deployment_stage = 'serve'
        if ($Image) {
            if ($Image -notmatch '^mb0101/ecommerce-store-users-api@sha256:[0-9a-f]{64}$') { throw 'Use an immutable Users image.' }
            $inputs.users_image = $Image
        }
    }
    'Swagger' {
        if (-not $inputs.deploy_users_app -or $inputs.users_deployment_stage -ne 'serve') { throw 'Complete serve before external API verification.' }
        if (-not (Test-UsersPublicIpv4 $ApiOperatorIpv4)) { throw 'Supply your current exact public IPv4 for temporary API access.' }
        $inputs.users_external_ingress_enabled = $true
        $inputs.api_operator_ipv4 = $ApiOperatorIpv4
    }
    'Internal' {
        $inputs.users_external_ingress_enabled = $false
        $inputs.api_operator_ipv4 = $null
        $inputs.min_replicas = 0
    }
}
Write-UsersInputs -Inputs $inputs -Path $InputsPath
Write-Host "Updated $InputsPath for $Stage. Review a NEW Terraform plan with -var-file=$InputsPath, then apply separately."
