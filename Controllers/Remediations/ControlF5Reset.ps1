. $PSScriptRoot\..\..\Config\Windows.ps1

function controlF5Reset {
    Write-Host "`n[*] Memulai Diagnosa dan Reset F5..." -ForegroundColor Cyan

    if ($IsWindows) {
        Write-Host "[Windows] [Tahap 1] Membersihkan sesi userland & cache browser SSO..." -ForegroundColor Yellow
        
        Get-Process | Where-Object { $_.ProcessName -match "f5|epsec|inspector" } | Stop-Process -Force -ErrorAction SilentlyContinue
        
        Remove-Item -Path "$env:LOCALAPPDATA\F5 Networks\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$env:TEMP\f5*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*" -Recurse -Force -ErrorAction SilentlyContinue
        
        ipconfig /flushdns | Out-Null
        
        Write-Host "Tahap 1 selesai." -ForegroundColor Green
        Write-Host "-> Silakan buka F5 Edge Client dan hubungkan ke profil SOC-GARUDA." -ForegroundColor Cyan
        
        $statusKoneksi = Read-Host "Apakah VPN berhasil terhubung? (y/n)"
        
        if ($statusKoneksi -match "^[yY]") {
            Write-Host "VPN berhasil dipulihkan di Tahap 1 tanpa memerlukan hak admin." -ForegroundColor Green
        } else {
            Write-Warning "Koneksi masih gagal. Memulai eskalasi ke Tahap 2 (Administrator)..."
            
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            
            $adminScript = {
                Write-Host "`n[Tahap 2] Memperbaiki Service VPN Windows dan Adapter F5..." -ForegroundColor Yellow
                
                # Pemisahan Set-Service agar tidak terjadi eror konversi Array ke String
                Set-Service -Name "RasMan" -StartupType Manual -ErrorAction SilentlyContinue
                Set-Service -Name "SstpSvc" -StartupType Manual -ErrorAction SilentlyContinue
                Start-Service -Name "RasMan", "SstpSvc" -ErrorAction SilentlyContinue
                
                Get-Service -Name *f5* -ErrorAction SilentlyContinue | Restart-Service -Force -ErrorAction SilentlyContinue
                
                Get-NetAdapter -Name "*F5*" -ErrorAction SilentlyContinue | Enable-NetAdapter -Confirm:$false -ErrorAction SilentlyContinue
                Get-NetAdapter -Name "*F5*" -ErrorAction SilentlyContinue | Restart-NetAdapter -Confirm:$false -ErrorAction SilentlyContinue
                
                Clear-DnsClientCache
                
                Write-Host "Tahap 2 selesai! OS Network Routing telah direset ke kondisi bersih." -ForegroundColor Green
                Write-Host "-> Silakan hubungkan ulang F5 Edge Client Anda." -ForegroundColor Cyan
                Read-Host "Tekan Enter untuk menutup jendela ini..."
            }
            
            if (-not $isAdmin) {
                Write-Host "Meminta akses UAC Administrator..." -ForegroundColor Yellow
                $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($adminScript.ToString()))
                Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -EncodedCommand $encoded"
            } else {
                Write-Host "Sesi sudah memiliki hak Admin, mengeksekusi langsung..." -ForegroundColor Cyan
                Invoke-Command -ScriptBlock $adminScript
            }
        }
    }
    elseif ($IsMacOS) {
        Write-Host "[macOS] Menghentikan proses F5 dan membersihkan DNS cache..." -ForegroundColor Yellow
        Get-Process | Where-Object { $_.Name -match "f5vpn|f5epi" } | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Host "Meminta akses sudo untuk flush DNS..." -ForegroundColor Cyan
        /usr/bin/sudo dscacheutil -flushcache
        /usr/bin/sudo killall -HUP mDNSResponder
        Write-Host "Reset macOS selesai." -ForegroundColor Green
    }
    elseif ($IsLinux) {
        Write-Host "[Linux] Menghentikan proses F5 dan membersihkan DNS cache..." -ForegroundColor Yellow
        Get-Process | Where-Object { $_.Name -match "f5fpc" } | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Host "Meminta akses sudo untuk flush DNS..." -ForegroundColor Cyan
        /usr/bin/sudo resolvectl flush-caches
        Write-Host "Reset Linux selesai." -ForegroundColor Green
    }
    else {
        Write-Warning "Sistem operasi tidak didukung untuk reset F5 otomatis."
    }
}