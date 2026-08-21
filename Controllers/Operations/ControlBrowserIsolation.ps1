. $PSScriptRoot\..\..\Middleware\MiddlewareBrowserIsolationLock.ps1
. $PSScriptRoot\..\..\Config\Windows.ps1

function controlBrowserIsolation{
    Write-Host "[*] Mempersiapkan Ruang Steril (Multi-Browser Isolation)..." @Net

    # 0. Self-Healing: Bersihkan folder Rasamala_* sisa crash/mati listrik sebelumnya
    $systemTemp = [System.IO.Path]::GetTempPath()
    $staleFolders = Get-ChildItem -Path $systemTemp -Filter "Rasamala_*" -Directory -ErrorAction SilentlyContinue
    if ($staleFolders) {
        Write-Host "  [!] Menemukan $($staleFolders.Count) folder sesi lama. Membersihkan..." @Pen
        foreach ($folder in $staleFolders) {
            Remove-Item -Path $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # 1. Pemetaan Path berdasarkan OS (Termasuk folder AppData untuk Standard User)
    $browserMappings = @()

    if ($IsWindows) {
        $localApp = $env:LOCALAPPDATA
        $browserMappings = @(
            @{ 
                Name = 'Chrome'; 
                Type = 'Chromium'; 
                Paths = @(
                    "C:\Program Files\Google\Chrome\Application\chrome.exe", 
                    "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
                    "$localApp\Google\Chrome\Application\chrome.exe"
                ) 
            }
            @{ 
                Name = 'Brave';  
                Type = 'Chromium'; 
                Paths = @(
                    "C:\Program Files\BraveSoftware\Brave-Browser\Application\brave.exe",
                    "C:\Program Files (x86)\BraveSoftware\Brave-Browser\Application\brave.exe",
                    "$localApp\BraveSoftware\Brave-Browser\Application\brave.exe"
                ) 
            }
            @{ 
                Name = 'Edge';   
                Type = 'Chromium'; 
                Paths = @(
                    "C:\Program Files\Microsoft\Edge\Application\msedge.exe",
                    "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
                    "$localApp\Microsoft\Edge\Application\msedge.exe"
                ) 
            }
            @{ 
                Name = 'Firefox';
                Type = 'Firefox';  
                Paths = @(
                    "C:\Program Files\Mozilla Firefox\firefox.exe", 
                    "C:\Program Files (x86)\Mozilla Firefox\firefox.exe",
                    "$localApp\Mozilla Firefox\firefox.exe"
                ) 
            }
        )
    }
    elseif ($IsLinux) {
        $browserMappings = @(
            @{ Name = 'Chrome'; Type = 'Chromium'; Paths = @('/usr/bin/google-chrome') }
            @{ Name = 'Brave';  Type = 'Chromium'; Paths = @('/usr/bin/brave-browser', '/snap/bin/brave') }
            @{ Name = 'Edge';   Type = 'Chromium'; Paths = @('/usr/bin/microsoft-edge') }
            @{ Name = 'Firefox';Type = 'Firefox';  Paths = @('/usr/bin/firefox', '/snap/bin/firefox') }
        )
    }
    elseif ($IsMacOS) {
        $browserMappings = @(
            @{ Name = 'Chrome'; Type = 'Chromium'; Paths = @('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome') }
            @{ Name = 'Brave';  Type = 'Chromium'; Paths = @('/Applications/Brave Browser.app/Contents/MacOS/Brave Browser') }
            @{ Name = 'Edge';   Type = 'Chromium'; Paths = @('/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge') }
            @{ Name = 'Firefox';Type = 'Firefox';  Paths = @('/Applications/Firefox.app/Contents/MacOS/firefox') }
        )
    }

    # 2. Cari semua browser yang terinstal
    $foundBrowsers = @()
    foreach ($map in $browserMappings) {
        foreach ($path in $map.Paths) {
            if (Test-Path $path) {
                $foundBrowsers += @{ Name = $map.Name; Type = $map.Type; Path = $path }
                break # Ketemu satu path untuk browser ini, lanjut cari browser jenis lain
            }
        }
    }

    if ($foundBrowsers.Count -eq 0) {
        Write-Error "Tidak ada browser yang ditemukan di sistem ini."
        return
    }

    Write-Host "  [-] Ditemukan $($foundBrowsers.Count) browser. Meluncurkan secara serentak..."

    $activeProcesses = @()
    $tempDirectories = @()

    # 3. Luncurkan masing-masing browser dengan profil terpisah
    foreach ($browser in $foundBrowsers) {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "Rasamala_$($browser.Name)_$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        $tempDirectories += $tempDir

        # --- TIMER SELF-DESTRUCT (BACKGROUND POLLING VIA ENCODED COMMAND) ---
        $timeoutSeconds = $TimePollingNormalSec
        $folderName = Split-Path $tempDir -Leaf

        $scriptBlockText = @"
`$ErrorActionPreference = 'SilentlyContinue'
while (`$true) {
    Start-Sleep -Seconds $timeoutSeconds
    
    `$active = Get-CimInstance Win32_Process | Where-Object { `$_.CommandLine -like '*$folderName*' }
    
    if (-not `$active) {
        if (Test-Path '$tempDir') {
            cmd.exe /c rmdir /s /q "$tempDir" 2> `$null
        }
        break
    }
}
"@

        $bytes = [System.Text.Encoding]::Unicode.GetBytes($scriptBlockText)
        $encodedCommand = [Convert]::ToBase64String($bytes)

        try {
            if ($IsWindows) {
                 Start-Process cmd.exe -ArgumentList "/c start /b powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand $encodedCommand" -WindowStyle Hidden
            } else {
                 Write-Warning "Background Polling (Encoded) diformat untuk Windows."
            }
            Write-Host "      [+] Timer Polling Base64 (Cek setiap $timeoutSeconds detik) aktif untuk: $folderName"
        }
        catch {
            Write-Warning "Gagal memasang Timer Background pada $($browser.Name)"
        }
        # -----------------------------------------------

        $browserArgs = @()
        if ($browser.Type -eq 'Chromium') {
            $browserArgs = @(
                "--user-data-dir=`"$tempDir`"", 
                "--incognito", 
                "--no-first-run", 
                "--no-default-browser-check",
                "--disable-extensions", 
                "--disable-sync", 
                "--disable-background-networking",
                "--disable-password-manager-reauthentication", 
                "--disable-save-password-bubble", 
                "`"$TargetUrl`""
            )
        }
        elseif ($browser.Type -eq 'Firefox') {
            $browserArgs = @(
                "-profile", "`"$tempDir`"", 
                "-private-window", 
                "`"$TargetUrl`""
            )
        }

        try {
            $process = Start-Process -FilePath $browser.Path -ArgumentList $browserArgs -PassThru -NoNewWindow
            $activeProcesses += $process
            Write-Host "      > $($browser.Name) diluncurkan (PID: $($process.Id))"
        }
        catch {
            Write-Warning "Gagal meluncurkan $($browser.Name): $_"
        }
    }

    middlewareBrowserIsolationLock

    # 4. Tahan Sesi Sampai Semua Browser Tertutup
    Write-Host "[+] Menunggu SELURUH browser ditutup sebelum pembersihan..." @Cha
    try {
        if ($activeProcesses.Count -gt 0) {
            Wait-Process -InputObject $activeProcesses -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "Terjadi gangguan saat memantau proses browser."
    }

    # 5. Pembersihan Otomatis (Cleanup Normal)
    Write-Host "[*] Semua browser telah ditutup. Menghancurkan seluruh jejak sesi..." @Pen
    Start-Sleep -Seconds $TimeCleanupDelaySec 
    foreach ($dir in $tempDirectories) {
        Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host "[v] Sesi steril berhasil dihancurkan." @App
}