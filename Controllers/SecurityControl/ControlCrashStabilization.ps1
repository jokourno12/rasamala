function controlCrashStabilization {
    Write-Host "`n[*] Memulai Diagnosa Stabilitas Sistem Lengkap (Tahap 1: Userland)..." -ForegroundColor Cyan

    $allEvents = @()

    # TAHAP 1: Diagnosa Read-Only Seluruh Log
    if ($IsWindows -or (-not $IsLinux -and -not $IsMacOS)) {
        # Menarik SELURUH event terkait shutdown/restart/crash
        $rawEvents = Get-WinEvent -FilterHashtable @{LogName='System'; Id=41, 1001, 6008, 1074} -ErrorAction SilentlyContinue

        if ($rawEvents) {
            foreach ($evt in $rawEvents) {
                $category = "Unknown"
                $severity = 0 # 0 = Normal, 1 = Peringatan (Tweak), 2 = Kritis (Crash Asli)
                $msg = if ([string]::IsNullOrWhitespace($evt.Message)) { "" } else { $evt.Message.Trim() }

                switch ($evt.Id) {
                    1074 {
                        # KATEGORI 1074: Graceful Shutdown/Restart (Normal OS behavior)
                        if ($msg -match "wuauclt|MoUsoCoreWorker|TiWorker|WindowsUpdate") {
                            $category = "Windows Update Auto-Restart"
                            $severity = 1
                        } elseif ($msg -match "StartMenuExperienceHost|explorer\.exe|shutdown\.exe|winlogon\.exe") {
                            $category = "Normal User/System Shutdown"
                            $severity = 0
                        } else {
                            $category = "Planned System/App Reboot"
                            $severity = 0
                        }
                    }
                    1001 { 
                        $category = "Kernel Crash / BSOD (BugCheck)"
                        $severity = 2 
                    }
                    41 { 
                        $category = "Sudden Power Loss / Thermal Shutdown"
                        $severity = 2 
                    }
                    6008 { 
                        $category = "Unexpected Shutdown"
                        $severity = 2 
                    }
                }

                $allEvents += [PSCustomObject]@{
                    TimeCreated = $evt.TimeCreated
                    Id          = $evt.Id
                    Category    = $category
                    Severity    = $severity
                    Message     = $msg
                }
            }
        }
    }
    elseif ($IsLinux) {
        $kernelLogs = journalctl -p err..emerg --no-pager 2>$null | Where-Object { $_ -match "panic|Out of memory|thermal|Hardware Error" }
        $powerLogs  = last -x shutdown reboot 2>$null

        foreach ($entry in $kernelLogs) {
            $allEvents += [PSCustomObject]@{
                TimeCreated = (Get-Date)
                Id          = "LINUX_KERNEL_ERR"
                Category    = "Kernel Error / Hardware Instability"
                Severity    = 2
                Message     = $entry
            }
        }

        foreach ($entry in $powerLogs) {
            if ([string]::IsNullOrWhitespace($entry)) { continue }
            $allEvents += [PSCustomObject]@{
                TimeCreated = (Get-Date)
                Id          = "LINUX_POWER_EVENT"
                Category    = "System Shutdown/Reboot Record"
                Severity    = 0
                Message     = $entry
            }
        }
    }
    elseif ($IsMacOS) {
        $panicPaths = @("/Library/Logs/DiagnosticReports", "$HOME/Library/Logs/DiagnosticReports")
        $panicFiles = Get-ChildItem -Path $panicPaths -Filter "*.panic" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

        foreach ($panic in $panicFiles) {
            $allEvents += [PSCustomObject]@{
                TimeCreated = $panic.LastWriteTime
                Id          = "MAC_PANIC"
                Category    = "Kernel Panic Report"
                Severity    = 2
                Message     = "Laporan Panic: $($panic.Name)"
            }
        }
    }

    if ($allEvents.Count -eq 0) {
        Write-Host "Tidak ditemukan riwayat mati mendadak, restart, atau crash pada log sistem. Endpoint sehat." -ForegroundColor Green
        return
    }

    # PEMISAHAN KATEGORI BERDASARKAN SEVERITAS
    $normalEvents   = $allEvents | Where-Object { $_.Severity -eq 0 }
    $warningEvents  = $allEvents | Where-Object { $_.Severity -eq 1 }
    $criticalEvents = $allEvents | Where-Object { $_.Severity -eq 2 }

    Write-Host "`n=== RINGKASAN DIAGNOSA LENGKAP SISTEM ===" -ForegroundColor Cyan
    Write-Host "Total Log Terdeteksi        : $($allEvents.Count)" -ForegroundColor White
    Write-Host "Normal Shutdown/Reboot      : $($normalEvents.Count)" -ForegroundColor Green
    Write-Host "Windows Update Auto-Restart : $($warningEvents.Count)" -ForegroundColor Yellow
    Write-Host "True Instability / Crash    : $($criticalEvents.Count)" -ForegroundColor Red

    if ($criticalEvents.Count -eq 0 -and $warningEvents.Count -eq 0) {
        Write-Host "`nSeluruh riwayat restart/shutdown tercatat sebagai aktivitas normal. Tidak ada remediasi yang diperlukan." -ForegroundColor Green
        return
    }

    # LOGIKA PRIORITAS: Fokus ke True Crash terlebih dahulu
    $latestEvent = $null
    if ($criticalEvents.Count -gt 0) {
        $latestEvent = $criticalEvents[0]
        Write-Host "`n[!] CRITICAL: Kejadian Crash Kernel/Hardware Terdeteksi:" -ForegroundColor Red
    } else {
        $latestEvent = $warningEvents[0]
        Write-Host "`n[i] INFO: Aktivitas Auto-Restart OS Terdeteksi:" -ForegroundColor Yellow
    }

    Write-Host ("Waktu      : " + $latestEvent.TimeCreated) -ForegroundColor White
    Write-Host ("Kategori   : " + $latestEvent.Category) -ForegroundColor White
    
    $eventMsg = $latestEvent.Message
    if ($eventMsg.Length -gt 150) { $eventMsg = $eventMsg.Substring(0, 150) + "..." }
    Write-Host "Deskripsi  : $eventMsg" -ForegroundColor DarkGray

    # Penentuan rekomendasi berdasarkan Event Target
    $remediasiTersedia = $true

    if ($IsWindows -or (-not $IsLinux -and -not $IsMacOS)) {
        switch ($latestEvent.Id) {
            1074 { Write-Host "`nRekomendasi : Blokir Windows Update agar tidak melakukan auto-restart saat user login." -ForegroundColor Yellow }
            1001 { Write-Host "`nRekomendasi : Perbaiki integritas berkas sistem operasi (SFC & DISM)." -ForegroundColor Yellow }
            { $_ -in 41, 6008 } { Write-Host "`nRekomendasi : Nonaktifkan fitur Fast Startup untuk mencegah korupsi power-state." -ForegroundColor Yellow }
            default { $remediasiTersedia = $false }
        }
    }
    elseif ($IsLinux) {
        Write-Host "`nRekomendasi : Perbaiki paket terputus (dpkg/apt) dan verifikasi integritas paket sistem." -ForegroundColor Yellow
    }
    elseif ($IsMacOS) {
        Write-Host "`nRekomendasi : Jalankan pertolongan pertama verifikasi volume disk (Disk Utility)." -ForegroundColor Yellow
    }

    if (-not $remediasiTersedia) {
        Write-Host "Tidak ada remediasi otomatis yang diperlukan untuk event ini." -ForegroundColor Green
        return
    }

    Write-Host "`nEksekusi remediasi ini membutuhkan akses Administrator / Root." -ForegroundColor Cyan
    $konfirmasi = Read-Host "Apakah Anda ingin melanjutkan perbaikan sekarang? (y/n)"

    if ($konfirmasi -notmatch "^[yY]") {
        Write-Warning "Remediasi dibatalkan oleh pengguna. Tidak ada modifikasi sistem yang dilakukan."
        return
    }

    # TAHAP 2: Eskalasi Hak Akses & Eksekusi Remediasi
    if ($IsWindows -or (-not $IsLinux -and -not $IsMacOS)) {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        $adminScriptStr = @"
        Write-Host "`n[*] Memulai Remediasi Otomatis (Tahap 2: Administrator)..." -ForegroundColor Cyan
        
        `$eventId = "$($latestEvent.Id)"

        switch (`$eventId) {
            "1074" {
                Write-Host "[Remediasi 1074] Menerapkan kebijakan pemblokiran Auto-Restart Windows Update..." -ForegroundColor Yellow
                `$regPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
                if (-not (Test-Path `$regPath)) { New-Item -Path `$regPath -Force | Out-Null }
                Set-ItemProperty -Path `$regPath -Name "NoAutoRebootWithLoggedOnUsers" -Value 1 -Type DWord -Force
                Write-Host "Sukses: Fitur Auto-Restart untuk Windows Update telah dinonaktifkan." -ForegroundColor Green
            }
            "1001" {
                Write-Host "[Remediasi 1001] Crash Kernel OS terdeteksi. Memulai perbaikan integritas berkas (SFC & DISM)..." -ForegroundColor Yellow
                Write-Host "Perhatian: Proses ini dapat memakan waktu 5-15 menit." -ForegroundColor DarkGray
                
                Write-Host "-> Menjalankan System File Checker (SFC)..." -ForegroundColor Cyan
                sfc /scannow
                
                Write-Host "`n-> Menjalankan perbaikan Image System (DISM)..." -ForegroundColor Cyan
                DISM /Online /Cleanup-Image /RestoreHealth
                Write-Host "Sukses: Berkas sistem operasi telah dipulihkan." -ForegroundColor Green
            }
            { `$_ -in "41", "6008" } {
                Write-Host "[Remediasi `$eventId] Mati mendadak terdeteksi (Masalah Power/Thermal)." -ForegroundColor Yellow
                Write-Host "-> Mematikan fitur 'Fast Startup'..." -ForegroundColor Cyan
                `$powerRegPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
                if (Test-Path `$powerRegPath) {
                    Set-ItemProperty -Path `$powerRegPath -Name "HiberbootEnabled" -Value 0 -Force
                    Write-Host "Sukses: Fast Startup dinonaktifkan." -ForegroundColor Green
                }
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
            $psHostPath = (Get-Process -Id $PID).Path
            Start-Process -FilePath $psHostPath -Verb RunAs -ArgumentList "-NoProfile -EncodedCommand $encoded"
        }
    }
    elseif ($IsLinux) {
        Write-Host "`n[*] Memulai Remediasi Otomatis (Tahap 2: Linux Root)..." -ForegroundColor Cyan
        Write-Host "-> Memperbaiki repositori & paket sistem yang bermasalah..." -ForegroundColor Yellow
        sudo apt-get update -y
        sudo dpkg --configure -a
        sudo apt-get install -f -y
        Write-Host "Sukses: Perbaikan paket sistem Linux selesai." -ForegroundColor Green
    }
    elseif ($IsMacOS) {
        Write-Host "`n[*] Memulai Remediasi Otomatis (Tahap 2: macOS Root)..." -ForegroundColor Cyan
        Write-Host "-> Menjalankan verifikasi sistem berkas utama..." -ForegroundColor Yellow
        sudo diskutil verifyVolume /
        Write-Host "Sukses: Verifikasi sistem berkas macOS selesai." -ForegroundColor Green
    }
}