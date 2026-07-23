@echo off
setlocal enabledelayedexpansion

set SRC=%~dp0..\src\SolidarityGrid.Node

echo Building project...
dotnet build "%SRC%" -c Release --nologo -q
if %ERRORLEVEL% neq 0 exit /b %ERRORLEVEL%

echo Starting SolidarityGrid Cluster...
echo.

:: Kill any existing dotnet processes on our ports
for /l %%p in (5001,1,5003) do (
    for /f "tokens=5" %%a in ('netstat -ano ^| findstr ":%%p "') do (
        if %%a neq 0 taskkill /f /pid %%a >nul 2>&1
    )
)
timeout /t 2 /nobreak >nul

:: Start NodeA (port 5001)
start "SolidarityGrid-NodeA" /min cmd /c "set NODE_ID=NodeA && set PEERS=http://localhost:5002,http://localhost:5003 && set ASPNETCORE_URLS=http://0.0.0.0:5001 && set ASPNETCORE_ENVIRONMENT=Development && dotnet run --project "%SRC%" --no-build -c Release"
timeout /t 2 /nobreak >nul

:: Start NodeB (port 5002)
start "SolidarityGrid-NodeB" /min cmd /c "set NODE_ID=NodeB && set PEERS=http://localhost:5001,http://localhost:5003 && set ASPNETCORE_URLS=http://0.0.0.0:5002 && set ASPNETCORE_ENVIRONMENT=Development && dotnet run --project "%SRC%" --no-build -c Release"
timeout /t 2 /nobreak >nul

:: Start NodeC (port 5003)
start "SolidarityGrid-NodeC" /min cmd /c "set NODE_ID=NodeC && set PEERS=http://localhost:5001,http://localhost:5002 && set ASPNETCORE_URLS=http://0.0.0.0:5003 && set ASPNETCORE_ENVIRONMENT=Development && dotnet run --project "%SRC%" --no-build -c Release"

echo.
echo Waiting for cluster to stabilize...
timeout /t 8 /nobreak >nul

echo.
echo Verifying cluster health:
for %%p in (5001 5002 5003) do (
    curl -s http://localhost:%%p/health >nul 2>&1
    if !ERRORLEVEL! equ 0 (
        echo   [OK] localhost:%%p
    ) else (
        echo   [FAIL] localhost:%%p
    )
)

echo.
echo Cluster is running!
echo   NodeA: http://localhost:5001
echo   NodeB: http://localhost:5002
echo   NodeC: http://localhost:5003
echo.
echo To stop: close the console windows or run: taskkill /f /fi "WINDOWTITLE eq SolidarityGrid-*"
echo To run chaos test: .\scripts\chaos-test.ps1
echo.

pause
