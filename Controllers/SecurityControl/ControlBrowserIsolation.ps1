. $PSScriptRoot\..\..\Middleware\MiddlewareBrowserIsolationLock.ps1
. $PSScriptRoot\..\..\Config\Windows.ps1

function controlBrowserIsolation {
    # 1. Resolusi biner LLRT lintas platform dari folder Helpers\Lib di root Rasamala
    $libDir = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', '..', 'Helpers', 'Lib'))
    $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
    $llrtBinName = $null

    if ($IsWindows -and $arch -eq 'X64') {
        $llrtBinName = 'llrt-windows-x64-no-sdk.exe'
    }
    elseif ($IsLinux -and $arch -eq 'X64') {
        $llrtBinName = 'llrt-linux-x64-no-sdk'
    }
    elseif ($IsMacOS -and $arch -eq 'Arm64') {
        $llrtBinName = 'llrt-darwin-arm64-no-sdk'
    }

    $llrtPath = if ($llrtBinName) { [System.IO.Path]::Combine($libDir, $llrtBinName) } else { $null }
    $llrtExists = $llrtPath -and (Test-Path $llrtPath)

    if ($llrtExists) {
        Write-Host "[*] Engine LLRT terdeteksi. Menggunakan mode orkestrasi Hybrid (LLRT Engine)..." -ForegroundColor Cyan

        # --- MODE HYBRID (LLRT Engine) ---
        $enginePath = [System.IO.Path]::Combine($PSScriptRoot, "engine", "EngineBrowserIsolation.js")
        $lockFile   = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "rasamala_session.lock")

        if (-not (Test-Path $enginePath)) {
            Write-Error "[!] Berkas engine tidak ditemukan di: $enginePath"
            return
        }

        # Pastikan izin eksekusi aktif pada biner Linux/macOS
        if ($IsLinux -or $IsMacOS) {
            chmod +x $llrtPath 2>$null
        }

        # Bersihkan sisa lock file dari sesi yang mungkin crash sebelumnya
        if (Test-Path $lockFile) { Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue }

        # Pastikan argumen posisi pertama tidak kosong agar urutan argv tetap konsisten
        $safeTargetUrl = if ([string]::IsNullOrWhiteSpace($TargetUrl)) { "about:blank" } else { $TargetUrl }

        $llrtArgs = @(
            "`"$enginePath`"",
            "`"$safeTargetUrl`"",
            "`"$lockFile`""
        )

        try {
            # 1. Jalankan LLRT secara asinkron murni
            Start-Process -FilePath $llrtPath -ArgumentList $llrtArgs -NoNewWindow

            # 2. Tunggu maksimal 5 detik sampai LLRT berhasil membuat Lock File
            $waitCount = 0
            while (-not (Test-Path $lockFile) -and $waitCount -lt 5) {
                Start-Sleep -Seconds 1
                $waitCount++
            }

            # 3. Panggil sistem pengaman sesi (In-App Lock)
            middlewareBrowserIsolationLock

            # 4. Tahan prompt PowerShell selama Lock File masih eksis
            while (Test-Path $lockFile) {
                Start-Sleep -Seconds 2
            }
        }
        catch {
            Write-Warning "Terjadi kegagalan rute LLRT: $_"
        }
    }
    else {
        $checkedTarget = if ($llrtPath) { $llrtPath } else { "$libDir (OS/Arch: $arch tidak didukung)" }
        Write-Warning "[!] Engine LLRT tidak ditemukan di: $checkedTarget"
        Write-Host "[*] Memicu mode Fallback (Pure PowerShell)..." -ForegroundColor Yellow

        # --- MODE FALLBACK (Pure PowerShell) ---
        Write-Host "[*] Mempersiapkan Ruang Steril (Multi-Browser Isolation)..."

        # 0. Self-Healing: Bersihkan folder Rasamala_* sisa crash/mati listrik sebelumnya
        $systemTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, '..', '..', 'IsolatedSessions'))
        if (-not (Test-Path $systemTemp)) { New-Item -ItemType Directory -Path $systemTemp -Force | Out-Null }

        $staleFolders = Get-ChildItem -Path $systemTemp -Filter "Rasamala_*" -Directory -ErrorAction SilentlyContinue
        if ($staleFolders) {
            Write-Host "  [!] Menemukan $($staleFolders.Count) folder sesi lama. Membersihkan..."
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
            )
        }
        elseif ($IsLinux) {
            $browserMappings = @(
                @{ Name = 'Chrome'; Type = 'Chromium'; Paths = @('/usr/bin/google-chrome') }
                @{ Name = 'Brave';  Type = 'Chromium'; Paths = @('/usr/bin/brave-browser', '/snap/bin/brave') }
                @{ Name = 'Edge';   Type = 'Chromium'; Paths = @('/usr/bin/microsoft-edge') }
            )
        }
        elseif ($IsMacOS) {
            $browserMappings = @(
                @{ Name = 'Chrome'; Type = 'Chromium'; Paths = @('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome') }
                @{ Name = 'Brave';  Type = 'Chromium'; Paths = @('/Applications/Brave Browser.app/Contents/MacOS/Brave Browser') }
                @{ Name = 'Edge';   Type = 'Chromium'; Paths = @('/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge') }
            )
        }

        # 2. Cari semua browser yang terinstal
        $foundBrowsers = @()
        foreach ($map in $browserMappings) {
            foreach ($path in $map.Paths) {
                if (Test-Path $path) {
                    $foundBrowsers += @{ Name = $map.Name; Type = $map.Type; Path = $path }
                    break
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
            $tempDir = Join-Path $systemTemp "Rasamala_$($browser.Name)_$(Get-Random)"
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
                }
                else {
                    Write-Warning "Background Polling (Encoded) diformat untuk Windows."
                }
                Write-Host "      [+] Timer Polling Base64 (Cek setiap $timeoutSeconds detik) aktif untuk: $folderName"
            }
            catch {
                Write-Warning "Gagal memasang Timer Background pada $($browser.Name)"
            }

            $browserArgs = @()
            if ($browser.Type -eq 'Chromium') {
                $browserArgs = @(
                    "--user-data-dir=$tempDir",
                    "--incognito",
                    "--no-first-run",
                    "--no-default-browser-check",
                    "--disable-extensions",
                    "--disable-sync",
                    "--disable-background-networking",
                    "--disable-password-manager-reauthentication",
                    "--disable-save-password-bubble",
                    $TargetUrl
                )
            }

            try {
                $outLog = Join-Path $tempDir "stdout.log"
                $errLog = Join-Path $tempDir "stderr.log"
                $process = Start-Process -FilePath $browser.Path -ArgumentList $browserArgs -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru -NoNewWindow
                $activeProcesses += $process
                Write-Host "      > $($browser.Name) diluncurkan (PID: $($process.Id))"
            }
            catch {
                Write-Warning "Gagal meluncurkan $($browser.Name): $_"
            }
        }

        middlewareBrowserIsolationLock

        # 4. Tahan Sesi Sampai Semua Browser Tertutup
        Write-Host "[+] Menunggu SELURUH browser ditutup sebelum pembersihan..."
        try {
            if ($activeProcesses.Count -gt 0) {
                Wait-Process -InputObject $activeProcesses -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-Warning "Terjadi gangguan saat memantau proses browser."
        }

        # 5. Pembersihan Otomatis (Cleanup Normal)
        Write-Host "[*] Semua browser telah ditutup. Menghancurkan seluruh jejak sesi..."
        Start-Sleep -Seconds $TimeCleanupDelaySec
        foreach ($dir in $tempDirectories) {
            Remove-Item -Path $dir -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host "[v] Sesi steril berhasil dihancurkan."
    }
}