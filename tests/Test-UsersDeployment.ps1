#Requires -Version 7.2
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts/UsersDeployment.Common.ps1')
$work = Join-Path ([System.IO.Path]::GetTempPath()) "users-infra-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $work | Out-Null
$path = Join-Path $work 'users-deployment.tfvars.json'
$image = 'mb0101/ecommerce-store-users-api@sha256:' + ('a' * 64)
$script:checks = 0
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
function Assert-Rejected([scriptblock]$Action, [string]$Message) {
    $before = Get-Content -LiteralPath $path -Raw
    $rejected = $false
    try { & $Action } catch { $rejected = $true }
    Assert-True $rejected $Message
    Assert-True ((Get-Content -LiteralPath $path -Raw) -ceq $before) 'Rejected operation changed inputs.'
}
function global:Test-UsersTerraform {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $global:LASTEXITCODE = 0
    if ($Arguments[-1] -eq 'users_foundation') {
        return '{"subscription_id":"11111111-1111-1111-1111-111111111111"}'
    }
    return '{"enabled":true,"name":"ca-ecommercestore-users-dev","resource_group_name":"rg-ecommercestore-users-dev"}'
}
function global:az {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $global:LASTEXITCODE = $global:UsersTestExitCode
    return $global:UsersTestAzureResponse
}
try {
    & (Join-Path $root 'scripts/Set-UsersDeployment.ps1') -Stage Foundation -InputsPath $path
    $inputs = Read-UsersInputs $path
    Assert-True (-not $inputs.deploy_users_app) 'Foundation unexpectedly enables app.'
    Assert-Rejected { & (Join-Path $root 'scripts/Set-UsersDeployment.ps1') -Stage Prepare -Image 'api:latest' -InputsPath $path } 'Floating image accepted.'
    & (Join-Path $root 'scripts/Set-UsersDeployment.ps1') -Stage Prepare -Image $image -InputsPath $path
    Assert-True ((Read-UsersInputs $path).deploy_users_app) 'Prepare did not enable app.'
    Assert-Rejected { & (Join-Path $root 'scripts/Set-UsersDeployment.ps1') -Stage Foundation -InputsPath $path } 'Foundation could delete an app.'
    Assert-Rejected { & (Join-Path $root 'scripts/Set-UsersDeployment.ps1') -Stage Serve -InputsPath $path } 'Serve accepted missing egress.'
    Assert-Rejected { & (Join-Path $root 'scripts/Set-UsersDeployment.ps1') -Stage Swagger -ApiOperatorIpv4 '198.51.100.3' -InputsPath $path } 'Prepare became public.'
    $inputs = Read-UsersInputs $path
    $inputs['future_setting'] = 'preserve-me'
    Write-UsersInputs $inputs $path
    $global:UsersTestExitCode = 0
    $global:UsersTestAzureResponse = '{"state":"Succeeded","addresses":["203.0.113.5","203.0.113.4","203.0.113.4"]}'
    & (Join-Path $root 'scripts/Set-UsersMongoEgress.ps1') -TerraformPath Test-UsersTerraform -InputsPath $path
    $inputs = Read-UsersInputs $path
    Assert-True ($inputs.users_mongo_egress_ipv4.Count -eq 2) 'Egress was not deduplicated.'
    Assert-True ($inputs.users_mongo_egress_ipv4['ip-203-0-113-4'] -eq '203.0.113.4') 'Egress key is not stable.'
    Assert-True ($inputs.users_image -eq $image -and $inputs.future_setting -eq 'preserve-me') 'Egress helper lost existing settings.'
    $before = Get-Content $path -Raw
    $global:UsersTestAzureResponse = '{"state":"Succeeded","addresses":["203.0.113.4","203.0.113.5"]}'
    & (Join-Path $root 'scripts/Set-UsersMongoEgress.ps1') -TerraformPath Test-UsersTerraform -InputsPath $path
    Assert-True ((Get-Content $path -Raw) -ceq $before) 'Egress rerun is not deterministic.'
    foreach ($response in @(
        '{"state":"Failed","addresses":["203.0.113.4"]}',
        '{"state":"Succeeded","addresses":[]}',
        '{"state":"Succeeded","addresses":["0.0.0.0"]}',
        '{"state":"Succeeded","addresses":["10.0.0.1"]}',
        '{"state":"Succeeded","addresses":["2001:db8::1"]}'
    )) {
        $global:UsersTestAzureResponse = $response
        Assert-Rejected { & (Join-Path $root 'scripts/Set-UsersMongoEgress.ps1') -TerraformPath Test-UsersTerraform -InputsPath $path } 'Invalid Azure observation accepted.'
    }
    $global:UsersTestExitCode = 1
    Assert-Rejected { & (Join-Path $root 'scripts/Set-UsersMongoEgress.ps1') -TerraformPath Test-UsersTerraform -InputsPath $path } 'Failed Azure command accepted.'
    $global:UsersTestExitCode = 0
    $global:LASTEXITCODE = 0 # The fake native-command failure above was expected and asserted.
    & (Join-Path $root 'scripts/Set-UsersDeployment.ps1') -Stage Serve -InputsPath $path
    Assert-Rejected { & (Join-Path $root 'scripts/Set-UsersDeployment.ps1') -Stage Prepare -Image $image -InputsPath $path } 'Serving app returned to prepare.'
    Assert-Rejected { & (Join-Path $root 'scripts/Set-UsersDeployment.ps1') -Stage Swagger -ApiOperatorIpv4 '192.168.1.1' -InputsPath $path } 'Private API operator address accepted.'
    & (Join-Path $root 'scripts/Set-UsersDeployment.ps1') -Stage Swagger -ApiOperatorIpv4 '198.51.100.3' -InputsPath $path
    $inputs = Read-UsersInputs $path
    Assert-True ($inputs.users_external_ingress_enabled -and $inputs.users_mongo_egress_ipv4.Count -eq 2) 'Swagger changed database access.'
    & (Join-Path $root 'scripts/Set-UsersDeployment.ps1') -Stage Internal -InputsPath $path
    $inputs = Read-UsersInputs $path
    Assert-True (-not $inputs.users_external_ingress_enabled -and $null -eq $inputs.api_operator_ipv4 -and $inputs.min_replicas -eq 0) 'Internal did not clear temporary access.'
    Assert-True ($inputs.users_deployment_stage -eq 'serve' -and $inputs.users_image -eq $image -and $inputs.users_mongo_egress_ipv4.Count -eq 2) 'Internal lost serving settings.'
    foreach ($address in @('0.0.0.0','10.0.0.1','127.0.0.1','172.16.0.1','192.168.1.1','169.254.1.1','224.0.0.1','999.0.0.1','203.0.113.1/24','::1')) {
        Assert-True (-not (Test-UsersPublicIpv4 $address)) "Invalid IPv4 accepted: $address"
    }
    foreach ($file in Get-ChildItem (Join-Path $root 'scripts') -Filter '*.ps1') {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        Assert-True ($errors.Count -eq 0) "PowerShell parse failed: $($file.Name)"
    }
    $guide = Get-Content (Join-Path $root 'README.md') -Raw
    foreach ($block in [regex]::Matches($guide, '(?s)```powershell\r?\n(.*?)```')) {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($block.Groups[1].Value, [ref]$tokens, [ref]$errors) | Out-Null
        Assert-True ($errors.Count -eq 0) "README PowerShell parse failed: $errors"
    }
    Write-Host "Passed $script:checks offline Users deployment checks."
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
    Remove-Item Function:\global:az, Function:\global:Test-UsersTerraform -ErrorAction SilentlyContinue
    Remove-Variable UsersTestExitCode, UsersTestAzureResponse -Scope Global -ErrorAction SilentlyContinue
}
