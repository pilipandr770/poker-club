# PowerShell script to start Hardhat node, deploy contract, and start http-server
# Run with: .\start-and-deploy.ps1
# To stop: Press Ctrl+C or run: Stop-Job -Name HardhatNode; Remove-Job -Name HardhatNode

Write-Host "=== Starting Poker DApp ===" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/3] Starting Hardhat node in background..." -ForegroundColor Green

# Stop existing node if running
$existing = Get-Job -Name HardhatNode -ErrorAction SilentlyContinue
if ($existing) {
    Stop-Job -Job $existing -ErrorAction SilentlyContinue
    Remove-Job -Job $existing -Force
    Write-Host "  → Stopped existing node" -ForegroundColor Yellow
}

# Start the node in background (listens on all interfaces for network access)
$nodeJob = Start-Job -Name HardhatNode -ScriptBlock {
    Set-Location $using:PWD
    npx hardhat node --hostname 0.0.0.0
}

# Wait for node to start
Write-Host "  → Waiting for node to start..." -ForegroundColor Gray
Start-Sleep -Seconds 4

Write-Host "[2/3] Deploying contract..." -ForegroundColor Green

# Run deployment
npx hardhat run scripts/deploy.js --network localhost

Write-Host ""
Write-Host "[3/3] Starting http-server on port 3000..." -ForegroundColor Green
Write-Host ""
Write-Host "=== DApp is ready! ===" -ForegroundColor Cyan
Write-Host "  Hardhat RPC: http://127.0.0.1:8545" -ForegroundColor White
Write-Host "  Frontend:    http://127.0.0.1:3000" -ForegroundColor White
Write-Host ""
Write-Host "Press Ctrl+C to stop both servers." -ForegroundColor Yellow
Write-Host ""

# Start http-server in foreground (listens on all interfaces)
npx http-server . -p 3000 -a 0.0.0.0 -c-1