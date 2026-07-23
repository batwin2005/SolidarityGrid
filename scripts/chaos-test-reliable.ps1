param(
    [int]$WaitBeforeKill = 3,
    [int]$WaitForRecovery = 12
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$src = Join-Path $root "src\SolidarityGrid.Node"

function Get-PidByPort($Port) {
    $result = netstat -ano | Select-String ":$Port\s" | Where-Object { $_ -notmatch "LISTENING" -or $_ -match "LISTENING" }
    $match = $result | Where-Object { $_ -match "LISTENING" }
    if ($match) {
        $parts = $match -split '\s+'
        return [int]$parts[-1]
    }
    return $null
}

function Kill-Port($Port) {
    $pid = Get-PidByPort $Port
    if ($pid) {
        Write-Host "  Killing PID $pid on port $Port..." -ForegroundColor DarkRed
        taskkill /f /pid $pid 2>&1 | Out-Null
        Start-Sleep -Milliseconds 500
    }
}

function Start-NodeOnPort($Id, $Port) {
    $peers = @()
    foreach ($p in @(5001, 5002, 5003)) {
        if ($p -ne $Port) { $peers += "http://localhost:$p" }
    }
    $peerStr = $peers -join ','

    $envVars = @{
        NODE_ID = $Id
        PEERS = $peerStr
        ASPNETCORE_URLS = "http://0.0.0.0:$Port"
        ASPNETCORE_ENVIRONMENT = "Development"
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "dotnet"
    $psi.Arguments = "run --project `"$src`" --no-build -c Release"
    $psi.WorkingDirectory = $src
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $psi.CreateNoWindow = $false
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Minimized

    foreach ($kv in $envVars.GetEnumerator()) {
        $psi.EnvironmentVariables[$kv.Key] = $kv.Value
    }

    $process = [System.Diagnostics.Process]::Start($psi)
    return $process
}

# ============================================================
# MAIN
# ============================================================

$host.ui.RawUI.ForegroundColor = "Cyan"
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗"
Write-Host "║      SolidarityGrid — Reliable Chaos Test        ║"
Write-Host "╚══════════════════════════════════════════════════╝"
$host.ui.RawUI.ForegroundColor = "Gray"
Write-Host ""

# Cleanup first
Write-Host "➤ Cleaning up previous instances..." -ForegroundColor Yellow
5001..5003 | ForEach-Object { Kill-Port $_ }
Start-Sleep -Seconds 2

# Build
Write-Host "➤ Building..." -ForegroundColor Yellow
dotnet build $src -c Release --nologo -q
Write-Host "  ✔ Build OK" -ForegroundColor Green

# Start cluster
Write-Host "`n➤ Starting cluster..." -ForegroundColor Yellow
$nodes = @(
    @{ Id = "NodeA"; Port = 5001 },
    @{ Id = "NodeB"; Port = 5002 },
    @{ Id = "NodeC"; Port = 5003 }
)

foreach ($n in $nodes) {
    Write-Host "  Starting $($n.Id) on :$($n.Port)..." -ForegroundColor Gray
    Start-NodeOnPort $n.Id $n.Port
    Start-Sleep -Seconds 3
}

Write-Host "  Waiting for cluster to stabilize..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# Verify health
Write-Host "`n➤ Health check:" -ForegroundColor Cyan
$allHealthy = $true
foreach ($n in $nodes) {
    try {
        $h = Invoke-RestMethod "http://localhost:$($n.Port)/health" -ErrorAction Stop -TimeoutSec 3
        Write-Host "  ✔ $($n.Id) :$($n.Port)" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ $($n.Id) :$($n.Port) — UNREACHABLE" -ForegroundColor Red
        $allHealthy = $false
    }
}

if (-not $allHealthy) {
    Write-Host "Cluster not healthy, aborting." -ForegroundColor Red
    exit 1
}

# ============================================================
# CHAOS TEST
# ============================================================
$host.ui.RawUI.ForegroundColor = "Cyan"
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗"
Write-Host "║              CHAOS TEST BEGINS                   ║"
Write-Host "╚══════════════════════════════════════════════════╝"
$host.ui.RawUI.ForegroundColor = "Gray"

$targetNode = $nodes[0]  # Always kill NodeA
Write-Host "`n➤ Sending payment to $($targetNode.Id) (port $($targetNode.Port))..." -ForegroundColor Yellow

$body = @{ amount = 99.95; currency = "USD" } | ConvertTo-Json
$response = Invoke-RestMethod "http://localhost:$($targetNode.Port)/pay" -Method Post -Body $body -ContentType "application/json"
$txId = $response.transactionId
Write-Host "  ✔ Transaction: $txId" -ForegroundColor Green
Write-Host "  ✔ Node: $($response.node)"
Write-Host "  ✔ Delay: $($response.estimatedDelayMs)ms"

Write-Host "`n➤ Waiting $WaitBeforeKill seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds $WaitBeforeKill

# Kill the target node using netstat
$host.ui.RawUI.ForegroundColor = "Red"
Write-Host "`n⚡ KILLING NodeA on port $($targetNode.Port)..." 
$pidToKill = Get-PidByPort $targetNode.Port
if ($pidToKill) {
    Write-Host "  Found PID $pidToKill on port $($targetNode.Port)"
    taskkill /f /pid $pidToKill 2>&1 | Out-Null
    Start-Sleep -Seconds 1
    $verifyDead = Get-PidByPort $targetNode.Port
    if (-not $verifyDead) {
        Write-Host "  ✔ NodeA confirmed DEAD" -ForegroundColor Red
    } else {
        Write-Host "  ⚠ NodeA still alive!" -ForegroundColor Yellow
    }
} else {
    Write-Host "  ⚠ No process found on port $($targetNode.Port)!" -ForegroundColor Yellow
}

$host.ui.RawUI.ForegroundColor = "Gray"
Write-Host "`n➤ Waiting $WaitForRecovery seconds for self-healing..." -ForegroundColor Yellow
Start-Sleep -Seconds $WaitForRecovery

# ============================================================
# VERIFY
# ============================================================
$host.ui.RawUI.ForegroundColor = "Cyan"
Write-Host "`n╔══════════════════════════════════════════════════╗"
Write-Host "║              VERIFICATION                        ║"
Write-Host "╚══════════════════════════════════════════════════╝"
$host.ui.RawUI.ForegroundColor = "Gray"
Write-Host ""

$verdict = "PASS"
$found = $false

foreach ($n in $nodes) {
    if ($n.Id -eq "NodeA") { continue }

    try {
        $txns = Invoke-RestMethod "http://localhost:$($n.Port)/transactions" -ErrorAction Stop -TimeoutSec 5
        $tx = $txns | Where-Object { $_.id -eq $txId }

        if ($tx) {
            $found = $true
            $st = if ($tx.state -is [int]) { @{0="Pending";1="Processing";2="Completed";3="Failed"}[$tx.state] } else { $tx.state }
            $owner = $tx.ownerNodeId

            if ($st -ne "Completed" -or $owner -eq "NodeA") {
                $verdict = "PARTIAL"
            }

            Write-Host "  $($n.Id) : state=$st owner=$owner" -ForegroundColor $(if ($st -eq "Completed" -and $owner -ne "NodeA") { "Green" } elseif ($st -eq "Completed") { "Yellow" } else { "Red" })
        } else {
            Write-Host "  $($n.Id) : transaction not found" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "  $($n.Id) : UNREACHABLE" -ForegroundColor Red
    }
}

Write-Host ""
$host.ui.RawUI.ForegroundColor = $(if ($verdict -eq "PASS") { "Green" } elseif ($verdict -eq "PARTIAL") { "Yellow" } else { "Red" })
Write-Host "║  CHAOS TEST $verdict  ║"
$host.ui.RawUI.ForegroundColor = "Gray"
Write-Host ""

# Cleanup
Write-Host "➤ Cleanup..." -ForegroundColor Yellow
5001..5003 | ForEach-Object { Kill-Port $_ }
Write-Host "Done." -ForegroundColor Green
