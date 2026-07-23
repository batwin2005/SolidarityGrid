param(
    [switch]$Kill,
    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"

$root = Split-Path $PSScriptRoot -Parent
$src = Join-Path $root "src\SolidarityGrid.Node"

function Start-Node {
    param($Id, $Port, $Peers)
    $env:NODE_ID = $Id
    $env:PEERS = $Peers
    $env:ASPNETCORE_URLS = "http://0.0.0.0:$Port"
    $env:ASPNETCORE_ENVIRONMENT = "Development"

    $logFile = Join-Path $root "logs\node-$Id.log"
    $null = New-Item -ItemType Directory -Path (Join-Path $root "logs") -Force

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "dotnet"
    $psi.Arguments = "run --project `"$src`""
    $psi.WorkingDirectory = $src
    $psi.EnvironmentVariables["NODE_ID"] = $Id
    $psi.EnvironmentVariables["PEERS"] = $Peers
    $psi.EnvironmentVariables["ASPNETCORE_URLS"] = "http://0.0.0.0:$Port"
    $psi.EnvironmentVariables["ASPNETCORE_ENVIRONMENT"] = "Development"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false

    $process = [System.Diagnostics.Process]::Start($psi)
    return $process
}

function Stop-Node {
    param($Port)
    $process = Get-Process -Name "dotnet" -ErrorAction SilentlyContinue `
        | Where-Object { $_.CommandLine -like "*$Port*" }
    if ($process) {
        $process | Stop-Process -Force
    }
}

if ($Kill) {
    Write-Host "Stopping all SolidarityGrid nodes..." -ForegroundColor Yellow
    5001..5003 | ForEach-Object { Stop-Node -Port $_ }
    Write-Host "Done." -ForegroundColor Green
    return
}

Write-Host "Building project..."
dotnet build "$src" -c Release --nologo -q
if ($LASTEXITCODE -ne 0) { throw "Build failed" }

if ($BuildOnly) {
    Write-Host "Build successful." -ForegroundColor Green
    return
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   SolidarityGrid - Local Cluster Startup     ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Kill any existing nodes
5001..5003 | ForEach-Object { Stop-Node -Port $_ }
Start-Sleep -Seconds 1

Write-Host "Starting NodeA on :5001..." -ForegroundColor Green
$p1 = Start-Node -Id "NodeA" -Port 5001 -Peers "http://localhost:5002,http://localhost:5003"

Start-Sleep -Seconds 1

Write-Host "Starting NodeB on :5002..." -ForegroundColor Green
$p2 = Start-Node -Id "NodeB" -Port 5002 -Peers "http://localhost:5001,http://localhost:5003"

Start-Sleep -Seconds 1

Write-Host "Starting NodeC on :5003..." -ForegroundColor Green
$p3 = Start-Node -Id "NodeC" -Port 5003 -Peers "http://localhost:5001,http://localhost:5002"

Write-Host ""
Write-Host "Cluster starting up. Waiting for nodes to stabilize..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

Write-Host ""
Write-Host "Verifying cluster health..." -ForegroundColor Cyan
foreach ($port in 5001..5003) {
    try {
        $health = Invoke-RestMethod "http://localhost:$port/health" -ErrorAction Stop
        Write-Host "  ✔ Port $port → $($health.nodeId) (transactions: $($health.transactionCount))" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ Port $port → UNREACHABLE" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "Cluster is running!" -ForegroundColor Green
Write-Host "  NodeA: http://localhost:5001"
Write-Host "  NodeB: http://localhost:5002"
Write-Host "  NodeC: http://localhost:5003"
Write-Host ""
Write-Host "To stop: .\scripts\run-local.ps1 -Kill" -ForegroundColor Yellow
Write-Host "To run chaos test: .\scripts\chaos-test.ps1" -ForegroundColor Yellow
Write-Host ""
