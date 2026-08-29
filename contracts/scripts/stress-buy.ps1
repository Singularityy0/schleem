param(
    [uint64]$Quantity = 1,
    [uint16]$SlippageBps = 500,
    [string]$MarketAddress,
    [string]$TokenAddress,
    [string]$RpcUrl,
    [string]$PrivateKey
)

$ErrorActionPreference = 'Stop'
if ($Quantity -eq 0) { throw 'Quantity must be greater than zero.' }
if ($SlippageBps -gt 10000) { throw 'SlippageBps cannot exceed 10,000.' }

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
$TokenAddress = if ($TokenAddress) { $TokenAddress } else { $env:MUSDC_ADDRESS }
$RpcUrl = if ($RpcUrl) { $RpcUrl } else { $env:MONAD_RPC_URL }
$PrivateKey = if ($PrivateKey) { $PrivateKey } else { $env:PRIVATE_KEY }
if ($PrivateKey -match '^[0-9a-fA-F]{64}$') { $PrivateKey = "0x$PrivateKey" }

if ($MarketAddress -notmatch '^0x[0-9a-fA-F]{40}$') { throw 'Set MARKET_ADDRESS.' }
if ($TokenAddress -notmatch '^0x[0-9a-fA-F]{40}$') { throw 'Set MUSDC_ADDRESS.' }
if ([string]::IsNullOrWhiteSpace($RpcUrl)) { throw 'Set MONAD_RPC_URL.' }
if ($PrivateKey -notmatch '^0x[0-9a-fA-F]{64}$') {
    throw 'Set PRIVATE_KEY to the funded buyer testnet wallet.'
}

$cast = Join-Path $env:USERPROFILE '.foundry\bin\cast.exe'
if (-not (Test-Path -LiteralPath $cast)) { $cast = 'cast' }

$epochRaw = (& $cast call $MarketAddress 'activeEpochId()(uint256)' --rpc-url $RpcUrl | Out-String).Trim()
$epochMatch = [regex]::Match($epochRaw, '^\d+')
if (-not $epochMatch.Success) { throw 'Could not read the active epoch.' }
$epochId = [System.Numerics.BigInteger]::Parse($epochMatch.Value)

$statusRaw = (& $cast call $MarketAddress 'epochStatus(uint256)(uint8)' $epochId --rpc-url $RpcUrl | Out-String).Trim()
$statusMatch = [regex]::Match($statusRaw, '^\d+')
if (-not $statusMatch.Success -or [int]$statusMatch.Value -ne 1) {
    throw "Epoch $epochId is not trading. Keep the Rust keeper running and retry."
}

$quoteLines = @(& $cast call $MarketAddress `
    'quote(uint256,uint256)((uint256,uint256,uint256,uint256,uint256,uint256),uint256,uint256)' `
    $epochId $Quantity --rpc-url $RpcUrl)
if ($quoteLines.Count -lt 3) { throw 'Could not parse the live quote.' }
$paymentMatch = [regex]::Match([string]$quoteLines[$quoteLines.Count - 2], '^\s*(\d+)')
if (-not $paymentMatch.Success) { throw 'Could not parse total payment from the live quote.' }
$payment = [System.Numerics.BigInteger]::Parse($paymentMatch.Groups[1].Value)
$maxPremium = (($payment * (10000 + $SlippageBps)) + 9999) / 10000

Write-Output "Epoch ${epochId}: buying $Quantity ticket(s)."
Write-Output "Quoted payment: $payment base units; max with slippage: $maxPremium base units."
& $cast send $TokenAddress 'approve(address,uint256)(bool)' $MarketAddress $maxPremium `
    --rpc-url $RpcUrl --private-key $PrivateKey
if ($LASTEXITCODE -ne 0) { throw 'mUSDC approval failed.' }

& $cast send $MarketAddress 'buy(uint256,uint256,uint256)(uint256)' `
    $epochId $Quantity $maxPremium --rpc-url $RpcUrl --private-key $PrivateKey
if ($LASTEXITCODE -ne 0) { throw 'Ticket purchase failed.' }
