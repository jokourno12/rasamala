function controlF5Reset{
    Write-Host "`n[*] Memulai F5 EPSEC Service Reset..." -ForegroundColor Cyan

    if ($IsWindows) {
        Write-Host "[Windows] Menghentikan proses F5 dan merestart service..."
        # Hentikan semua background process F5
        Get-Process | Where-Object { $_.Name -match "f5|f5ep" } | Stop-Process -Force -ErrorAction SilentlyContinue
        
        # Restart service EPSEC dan VPN
        Restart-Service -Name "f5epsv", "F5BIGIPEdgeClientService" -Force -ErrorAction SilentlyContinue
        
        # Flush DNS
        Clear-DnsClientCache
        
        Write-Host "Reset Windows selesai." -ForegroundColor Green
    }
    elseif ($IsMacOS) {
        Write-Host "[macOS] Menghentikan proses F5 dan membersihkan DNS cache..."
        # Hentikan daemon F5 di macOS
        Get-Process | Where-Object { $_.Name -match "f5vpn|f5epi" } | Stop-Process -Force -ErrorAction SilentlyContinue
        
        # macOS memerlukan akses root untuk flush DNS
        Write-Host "Meminta akses sudo untuk flush DNS..." -ForegroundColor Yellow
        /usr/bin/sudo dscacheutil -flushcache
        /usr/bin/sudo killall -HUP mDNSResponder
        
        Write-Host "Reset macOS selesai." -ForegroundColor Green
    }
    elseif ($IsLinux) {
        Write-Host "[Linux] Menghentikan proses F5 dan membersihkan DNS cache..."
        # F5 CLI client di Linux biasanya f5fpc
        Get-Process | Where-Object { $_.Name -match "f5fpc" } | Stop-Process -Force -ErrorAction SilentlyContinue
        
        # Flush DNS bergantung pada distro
        Write-Host "Meminta akses sudo untuk flush DNS..." -ForegroundColor Yellow
        /usr/bin/sudo resolvectl flush-caches
        
        Write-Host "Reset Linux selesai." -ForegroundColor Green
    }
    else {
        Write-Warning "Sistem operasi tidak didukung untuk reset F5 otomatis."
    }
}