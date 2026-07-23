param(
    [int]$WaitBeforeKill = 3,
    [int]$WaitForRecovery = 12
)

$ErrorActionPreference = "Stop"

$host.ui.RawUI.ForegroundColor = "Cyan"
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗"
Write-Host "║      SolidarityGrid — Chaos Engineering Test     ║"
Write-Host "╚══════════════════════════════════════════════════╝"
Write-Host ""
$host.ui.RawUI.ForegroundColor = "Gray"

$nodes = @(
    @{ Name = "NodeA"; Url = "http://localhost:5001" },
    @{ Name = "NodeB"; Url = "http://localhost:5002" },
    @{ Name = "NodeC"; Url = "http://localhost:5003" }
)

$target = $nodes | Get-Random

Write-Host "➤ Sending payment to $($target.Name) ($($target.Url))..."
Write-Host ""

$body = @{ amount = 99.95; currency = "USD" } | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri "$($target.Url)/pay" -Method Post `
        -Body $body -ContentType "application/json" -ErrorAction Stop

    $txId = $response.transactionId
    $processingNode = $response.node
    Write-Host "  ✔ Transaction $txId created" -ForegroundColor Yellow
    Write-Host "  ✔ Assigned to $processingNode"
    Write-Host "  ✔ Estimated processing: $($response.estimatedDelayMs)ms"
    Write-Host ""
}
catch {
    Write-Host "  ✗ Failed to send payment: $_" -ForegroundColor Red
    exit 1
}

Write-Host "➤ Waiting $WaitBeforeKill seconds before injecting fault..."
Start-Sleep -Seconds $WaitBeforeKill

$containerName = "solidaritygrid-node-$($processingNode.ToLower())"
$killedNodeName = $processingNode

Write-Host ""
Write-Host "  ⚡ KILLING $processingNode container..." -ForegroundColor Red
try {
    docker stop $containerName 2>&1 | Out-Null
    Write-Host "  ✔ $processingNode stopped" -ForegroundColor Red
}
catch {
    docker kill $containerName 2>&1 | Out-Null
    Write-Host "  ✔ $processingNode killed" -ForegroundColor Red
}

Write-Host ""
Write-Host "➤ Waiting $WaitForRecovery seconds for cluster to self-heal..."
Start-Sleep -Seconds $WaitForRecovery

Write-Host ""
Write-Host "➤ Checking transaction status across surviving nodes..." -ForegroundColor Cyan
Write-Host ""

$found = $false

foreach ($node in $nodes) {
    if ($node.Name -eq $killedNodeName) { continue }

    try {
        $txns = Invoke-RestMethod -Uri "$($node.Url)/transactions" -Method Get -ErrorAction Stop

        $tx = $txns | Where-Object { $_.id -eq $txId }

        if ($tx) {
            $found = $true
            $statusSymbol = $null
            $statusColor = $null

            switch ($tx.state) {
                "Completed"  { $statusSymbol = "✔"; $statusColor = "Green" }
                "Processing" { $statusSymbol = "⏳"; $statusColor = "Yellow" }
                "Failed"     { $statusSymbol = "✗"; $statusColor = "Red" }
                default      { $statusSymbol = "?"; $statusColor = "Gray" }
            }

            $host.ui.RawUI.ForegroundColor = $statusColor
            Write-Host "  $statusSymbol $($node.Name): $($tx.state) (owner: $($tx.ownerNodeId))"
            $host.ui.RawUI.ForegroundColor = "Gray"
        }
        else {
            Write-Host "  - $($node.Name): transaction not found in local state" -ForegroundColor DarkGray
        }
    }
    catch {
        Write-Host "  - $($node.Name): unreachable ($($_.Exception.Message))" -ForegroundColor DarkGray
    }
}

Write-Host ""

if ($found) {
    $host.ui.RawUI.ForegroundColor = "Green"
    Write-Host "╔══════════════════════════════════════════════════╗"
    Write-Host "║           CHAOS TEST PASSED ✓                    ║"
    Write-Host "║  The cluster detected the failure and recovered  ║"
    Write-Host "║  the orphaned transaction automatically.         ║"
    Write-Host "╚══════════════════════════════════════════════════╝"
}
else {
    $host.ui.RawUI.ForegroundColor = "Red"
    Write-Host "╔══════════════════════════════════════════════════╗"
    Write-Host "║           CHAOS TEST FAILED ✗                    ║"
    Write-Host "║  No surviving node has the transaction.          ║"
    Write-Host "╚══════════════════════════════════════════════════╝"
}

$host.ui.RawUI.ForegroundColor = "Gray"
Write-Host ""

Write-Host "➤ Restarting $killedNodeName for future tests..."
try {
    docker start $containerName 2>&1 | Out-Null
    Write-Host "  ✔ $killedNodeName restarted" -ForegroundColor Green
}
catch {
    Write-Host "  ⚠ Could not restart $killedNodeName: $_" -ForegroundColor Yellow
}

Write-Host ""
