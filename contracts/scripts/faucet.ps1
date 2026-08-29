param([string]$TokenAddress, [string]$RpcUrl, [string]$PrivateKey)

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
$TokenAddress = if ($TokenAddress) { $TokenAddress } else { $env:MUSDC_ADDRESS }
$RpcUrl = if ($RpcUrl) { $RpcUrl } else { $env:MONAD_RPC_URL }
$PrivateKey = if ($PrivateKey) { $PrivateKey } else { $env:PRIVATE_KEY }

if ($PrivateKey -match '^[0-9a-fA-F]{64}$') {
    $PrivateKey = "0x$PrivateKey"
}

if ($TokenAddress -notmatch '^0x[0-9a-fA-F]{40}$') {
    throw 'Set MUSDC_ADDRESS to the deployed TestUSDC contract.'
}
if ([string]::IsNullOrWhiteSpace($RpcUrl)) {
    throw 'Set MONAD_RPC_URL.'
}
if ($PrivateKey -notmatch '^0x[0-9a-fA-F]{64}$') {
    throw 'Set PRIVATE_KEY to the claiming testnet wallet. Never use a wallet with real assets.'
}

$cast = Join-Path $env:USERPROFILE '.foundry\bin\cast.exe'
if (-not (Test-Path -LiteralPath $cast)) {
    $cast = 'cast'
}

Write-Output 'Claiming 500 mUSDC. This wallet can claim again after 24 hours.'
& $cast send $TokenAddress 'faucet()' --rpc-url $RpcUrl --private-key $PrivateKey
