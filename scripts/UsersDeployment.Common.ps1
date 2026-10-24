Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-UsersPublicIpv4 {
    param([AllowNull()][string]$Address)
    $ip = $null
    if ($Address -notmatch '^(\d{1,3}\.){3}\d{1,3}$' -or
        -not [System.Net.IPAddress]::TryParse($Address, [ref]$ip)) { return $false }
    $b = $ip.GetAddressBytes()
    return $b.Length -eq 4 -and $b[0] -notin @(0, 10, 127) -and $b[0] -lt 224 -and
        -not ($b[0] -eq 169 -and $b[1] -eq 254) -and
        -not ($b[0] -eq 172 -and $b[1] -ge 16 -and $b[1] -le 31) -and
        -not ($b[0] -eq 192 -and $b[1] -eq 168)
}

function Read-UsersInputs {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{
            deploy_users_app = $false
            users_image = $null
            users_deployment_stage = 'prepare'
            users_mongo_egress_ipv4 = @{}
            users_external_ingress_enabled = $false
            api_operator_ipv4 = $null
            min_replicas = 0
        }
    }
    $inputs = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    if ($inputs -isnot [System.Collections.IDictionary] -or
        -not $inputs.Contains('deploy_users_app') -or -not $inputs.Contains('users_deployment_stage') -or
        -not $inputs.Contains('users_mongo_egress_ipv4')) { throw 'Invalid Users deployment input file.' }
    return $inputs
}

function Write-UsersInputs {
    param([System.Collections.IDictionary]$Inputs, [string]$Path)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $temporary = "$fullPath.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        $Inputs | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporary -Encoding utf8
        Move-Item -LiteralPath $temporary -Destination $fullPath -Force
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
    }
}

function Get-UsersTerraformOutput {
    param([string]$TerraformPath, [string]$Name)
    $result = & $TerraformPath output -json $Name
    if ($LASTEXITCODE -ne 0) { throw "Terraform output $Name failed; inputs were not changed." }
    return ($result -join "`n") | ConvertFrom-Json -AsHashtable
}
