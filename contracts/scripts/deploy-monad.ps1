param([string]$RpcUrl)

$ErrorActionPreference = 'Stop'
$contractsRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $contractsRoot '.env'
if (Test-Path -LiteralPath $envPath) {
    foreach ($line in Get-Content -LiteralPath $envPath) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)\s*$') {
            $name = $Matches[1]
            if (-not (Test-Path -LiteralPath "Env:$name")) {
                Set-Item -LiteralPath "Env:$name" -Value $Matches[2].Trim()
            }
        }
    }
}
$RpcUrl = if ($RpcUrl) { $RpcUrl } else { $env:MONAD_RPC_URL }
$privateKey = $env:PRIVATE_KEY
if ($privateKey -match '^[0-9a-fA-F]{64}$') {
    $privateKey = "0x$privateKey"
    $env:PRIVATE_KEY = $privateKey
}

if ([string]::IsNullOrWhiteSpace($RpcUrl)) {
    throw 'Set MONAD_RPC_URL.'
}
if ($privateKey -notmatch '^0x[0-9a-fA-F]{64}$') {
    throw 'Set PRIVATE_KEY to a funded testnet-only deployer wallet.'
}

$forge = Join-Path $env:USERPROFILE '.foundry\bin\forge.exe'
if (-not (Test-Path -LiteralPath $forge)) {
    $forge = 'forge'
}

Push-Location $contractsRoot
try {
    & $forge script script/Deploy.s.sol:Deploy --rpc-url $RpcUrl --broadcast -vvvv
} finally {
    Pop-Location
}
