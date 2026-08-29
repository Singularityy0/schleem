param(
    [Parameter(Mandatory = $true)][string]$Recipient,
    [string]$AmountMon = '20',
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

$RpcUrl = if ($RpcUrl) { $RpcUrl } else { $env:MONAD_RPC_URL }
$privateKey = $env:PRIVATE_KEY
if ($privateKey -match '^[0-9a-fA-F]{64}$') {
    $privateKey = "0x$privateKey"
}

if ($Recipient -notmatch '^0x[0-9a-fA-F]{40}$') {
    throw 'Recipient must be a valid EVM address.'
}
if ($AmountMon -notmatch '^\d+(\.\d+)?$' -or [decimal]$AmountMon -le 0) {
    throw 'AmountMon must be a positive number.'
}
if ([string]::IsNullOrWhiteSpace($RpcUrl)) {
    throw 'Set MONAD_RPC_URL.'
}
if ($privateKey -notmatch '^0x[0-9a-fA-F]{64}$') {
    throw 'Set PRIVATE_KEY in contracts/.env to the funded sender wallet.'
}

$cast = Join-Path $env:USERPROFILE '.foundry\bin\cast.exe'
if (-not (Test-Path -LiteralPath $cast)) {
    $cast = 'cast'
}

Write-Output "Sending $AmountMon testnet MON to $Recipient."
& $cast send $Recipient `
    --value "${AmountMon}ether" `
    --rpc-url $RpcUrl `
    --private-key $privateKey
