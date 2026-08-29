param(
    [Parameter(Mandatory = $true)][string]$NewKeeperAddress,
    [string]$MarketAddress,
    [string]$RpcUrl
)

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

$MarketAddress = if ($MarketAddress) { $MarketAddress } else { $env:MARKET_ADDRESS }
$RpcUrl = if ($RpcUrl) { $RpcUrl } else { $env:MONAD_RPC_URL }
$privateKey = $env:PRIVATE_KEY
if ($privateKey -match '^[0-9a-fA-F]{64}$') {
    $privateKey = "0x$privateKey"
}

if ($NewKeeperAddress -notmatch '^0x[0-9a-fA-F]{40}$') {
    throw 'NewKeeperAddress must be a valid EVM address.'
}
if ($MarketAddress -notmatch '^0x[0-9a-fA-F]{40}$') {
    throw 'Set MARKET_ADDRESS in contracts/.env or pass -MarketAddress.'
}
if ([string]::IsNullOrWhiteSpace($RpcUrl)) {
    throw 'Set MONAD_RPC_URL.'
}
if ($privateKey -notmatch '^0x[0-9a-fA-F]{64}$') {
    throw 'Set PRIVATE_KEY in contracts/.env to the current market owner key.'
}

$cast = Join-Path $env:USERPROFILE '.foundry\bin\cast.exe'
if (-not (Test-Path -LiteralPath $cast)) {
    $cast = 'cast'
}

Write-Output "Setting market keeper to $NewKeeperAddress on Monad Testnet."
& $cast send $MarketAddress 'setKeeper(address)' $NewKeeperAddress `
    --rpc-url $RpcUrl `
    --private-key $privateKey
