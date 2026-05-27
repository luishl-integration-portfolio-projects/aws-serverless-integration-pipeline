param(
    [switch]$All
)

Write-Host "===================================" -ForegroundColor Cyan
Write-Host " LocalStack Lambda Cleanup Script" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan

# 1. List all containers first (debug visibility)
Write-Host "`n[INFO] Listing all Podman containers..." -ForegroundColor Cyan
podman ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"

# 2. Find Lambda executor containers (robust match)
Write-Host "`n[INFO] Searching Lambda executor containers..." -ForegroundColor Cyan

$executors = podman ps -a --format "{{.Names}}" |
    Where-Object { $_ -match "lambda" -or $_ -match "procesador-pedidos" }

$count = 0

foreach ($cname in $executors) {
    $cname = $cname.Trim()
    if (-not $cname) { continue }

    Write-Host "  -> Removing container: $cname" -ForegroundColor Yellow

    # NO SILENCIO DE ERRORES (importante para debug)
    try {
        podman rm -f $cname
        Write-Host "     [OK] Removed $cname" -ForegroundColor Green
        $count++
    }
    catch {
        Write-Host "     [WARN] Failed to remove $cname : $_" -ForegroundColor Red
    }
}

if ($count -eq 0) {
    Write-Host "  (no Lambda executor containers found)" -ForegroundColor DarkGray
} else {
    Write-Host "`n[OK] Removed $count Lambda executor container(s)." -ForegroundColor Green
}

# 3. Optional full reset
if ($All) {
    Write-Host "`n[INFO] Stopping main LocalStack container..." -ForegroundColor Yellow

    try {
        podman rm -f localstack-pipeline
        Write-Host "[OK] LocalStack container removed." -ForegroundColor Green
    }
    catch {
        Write-Host "[WARN] Could not remove LocalStack container: $_" -ForegroundColor Red
    }

    Write-Host "`n[INFO] You can now restart with: .\scripts\start_localstack.ps1" -ForegroundColor Cyan
}

# 4. Post-clean verification
Write-Host "`n[INFO] Verifying remaining containers..." -ForegroundColor Cyan
podman ps -a --format "table {{.Names}}\t{{.Status}}"

Write-Host "`n[DONE] Cleanup finished." -ForegroundColor Green