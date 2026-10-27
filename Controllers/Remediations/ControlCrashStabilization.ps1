function controlCrashStabilzation {
    Write-Host "`n[*] Memulai Diagnosa Stabilitas Sistem (Tahap 1: Userland)..." -ForegroundColor Cyan

    # TAHAP 1: Diagnosa Read-Only (Tidak butuh hak admin)
    $latestEvent = Get-WinEvent -FilterHashtable @{LogName='System'; Id=41, 1001, 6008, 1074} -MaxEvents 1 -ErrorAction SilentlyContinue

    if (-not $latestEvent) {
        Write-Host "Tidak ditemukan riwayat mati mendadak atau crash baru-baru ini. Endpoint sehat." -ForegroundColor Green
        return
    }

    Write-Host ("Ditemukan Event ID " + $latestEvent.Id + " pada " + $latestEvent.TimeCreated) -ForegroundColor Red
    
    # Memotong pesan panjang agar tampilan terminal tetap rapi
    $eventMsg = $latestEvent.Message
    if ($eventMsg.Length -gt 150) { $eventMsg = $eventMsg.Substring(0, 150) + "..." }
    Write-Host "Deskripsi: $eventMsg" -ForegroundColor DarkGray

    # Menentukan status rekomendasi
    $remediasiTersedia = $true
    switch ($latestEvent.Id) {
        1074 { Write-Host "Rekomendasi : Blokir Windows Update agar tidak melakukan auto-restart saat user login." -ForegroundColor Yellow }
        1001 { Write-Host "Rekomendasi : Perbaiki integritas berkas sistem operasi (SFC & DISM)." -ForegroundColor Yellow }
        { $_ -in 41, 6008 } { Write-Host "Rekomendasi : Nonaktifkan fitur Fast Startup untuk mencegah korupsi power-state." -ForegroundColor Yellow }
        default { $remediasiTersedia = $false }
    }

    if (-not $remediasiTersedia) {
        Write-Host "Tidak ada remediasi otomatis yang diperlukan untuk event ini." -ForegroundColor Green
        return
    }

    # Konfirmasi sebelum eskalasi ke TAHAP 2
    Write-Host "`nEksekusi remediasi ini membutuhkan akses Administrator." -ForegroundColor Cyan
    $konfirmasi = Read-Host "Apakah Anda ingin melanjutkan perbaikan sekarang? (y/n)"

    if ($konfirmasi -notmatch "^[yY]") {
        Write-Warning "Remediasi dibatalkan oleh pengguna. Tidak ada modifikasi sistem yang dilakukan."
        return
    }

    # TAHAP 2: Eskalasi Administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    # Membungkus logika admin dalam bentuk string agar parameter (EventId) mudah disuntikkan ke proses UAC baru
    $adminScriptStr = @"
    Write-Host "`n[*] Memulai Remediasi Otomatis (Tahap 2: Administrator)..." -ForegroundColor Cyan
    
    `$eventId = $($latestEvent.Id)

    switch (`$eventId) {
        1074 {
            Write-Host "[Remediasi 1074] Menerapkan kebijakan pemblokiran Auto-Restart Windows Update..." -ForegroundColor Yellow
            `$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
            if (-not (Test-Path `$regPath)) { New-Item -Path `$regPath -Force | Out-Null }
            Set-ItemProperty -Path `$regPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force
            Write-Host "Sukses: Fitur Auto-Restart untuk Windows Update telah dinonaktifkan." -ForegroundColor Green
        }
        1001 {
            Write-Host "[Remediasi 1001] Crash Kernel OS terdeteksi. Memulai perbaikan integritas berkas (SFC & DISM)..." -ForegroundColor Yellow
            Write-Host "Perhatian: Proses ini dapat memakan waktu 5-15 menit." -ForegroundColor DarkGray
            
            Write-Host "-> Menjalankan System File Checker (SFC)..." -ForegroundColor Cyan
            sfc /scannow | Out-Null
            
            Write-Host "-> Menjalankan perbaikan Image System (DISM)..." -ForegroundColor Cyan
            DISM /Online /Cleanup-Image /RestoreHealth | Out-Null
            Write-Host "Sukses: Berkas sistem operasi telah dipulihkan." -ForegroundColor Green
        }
        { `$_ -in 41, 6008 } {
            Write-Host "[Remediasi `$eventId] Mati mendadak terdeteksi (Masalah Power/Thermal)." -ForegroundColor Yellow
            Write-Host "-> Mematikan fitur 'Fast Startup'..." -ForegroundColor Cyan
            `$powerRegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
            if (Test-Path `$powerRegPath) {
                Set-ItemProperty -Path `$powerRegPath -Name "HiberbootEnabled" -Value 0 -Force
            }
            Write-Host "Sukses: Fast Startup dinonaktifkan." -ForegroundColor Green
        }
    }

    Write-Host "`nTahap remediasi selesai." -ForegroundColor Green
    Read-Host "Tekan Enter untuk menutup jendela ini..."
"@

    if ($isAdmin) {
        Write-Host "Sesi saat ini sudah memiliki hak Admin, mengeksekusi langsung..." -ForegroundColor Cyan
        $scriptBlock = [scriptblock]::Create($adminScriptStr)
        Invoke-Command -ScriptBlock $scriptBlock
    } else {
        Write-Host "Meminta akses UAC Administrator..." -ForegroundColor Yellow
        $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($adminScriptStr))
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -EncodedCommand $encoded"
    }
}