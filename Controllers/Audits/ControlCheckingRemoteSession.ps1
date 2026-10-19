function controlCheckingRemoteSession{
    Write-Host "`n[Windows] Memeriksa Status Remote Session & Sustainability..." @Net
    
    # [TAMBAHAN: Mendefinisikan path untuk LiteDB dan database sustainability.db]
    $databasePath = "$PSScriptRoot\..\..\Database"
    $libPath = "$PSScriptRoot\..\..\Helpers\Lib"
    $dbFile = "$databasePath\sustainability.db"
    $liteDbDll = "$libPath\LiteDB.dll"

    $sessions = @()
    $remoteSessionData = $null

    # ==========================================
    # 1. WINDOWS: Menggunakan 'quser.exe'
    # ==========================================
    if ($IsWindows) {
        $quserOutput = quser.exe 2>$null
        
        if ($quserOutput -and $quserOutput.Count -gt 1) {
            for ($i = 1; $i -lt $quserOutput.Count; $i++) {
                $line = $quserOutput[$i] -replace '^>', ' '
                
                if ($line -match '^\s*(\S+)\s+([a-zA-Z0-9\-\#]+)?\s+(\d+)\s+([a-zA-Z]+)') {
                    $username    = $matches[1]
                    $sessionName = if ([string]::IsNullOrWhiteSpace($matches[2])) { "Disconnected" } else { $matches[2] }
                    $state       = $matches[4]
                    
                    $isRemote = $sessionName -match "rdp|ssh|winrm"
                    
                    $sessions += [PSCustomObject]@{
                        Username    = $username
                        SessionType = if ($isRemote) { "Remote ($sessionName)" } else { "Local ($sessionName)" }
                        RemoteHost  = if ($isRemote) { "Unknown/RDP" } else { "localhost" }
                        IsRemote    = $isRemote
                        State       = $state
                    }
                }
            }
        }

        # Dapatkan Model Hardware Windows
        $hwInfo = Get-CimInstance Win32_ComputerSystem
        #$hwInfo = [PSCustomObject]@{ Manufacturer = "Dell Inc."; Model = "OptiPlex 3000" }
        $hardwareModel = "$($hwInfo.Manufacturer) $($hwInfo.Model)"
        
        # [TAMBAHAN: Logika pengecekan EPEAT Status dari LiteDB]
        $epeatStatus = "Unregistered" # Default status jika tidak ditemukan
        
        if (Test-Path $dbFile) {
            if (Test-Path $liteDbDll) {
                Add-Type -Path $liteDbDll
                $db = New-Object LiteDB.LiteDatabase("Filename=$dbFile;Connection=shared")
                $collection = $db.GetCollection("epeat_products")
                
                # Membersihkan nama manufacturer (Misal: "Dell Inc." menjadi "Dell") agar mudah dicocokkan dengan "DELL" di DB
                $cleanManufacturer = $hwInfo.Manufacturer -replace '(?i)\s*Inc\.?|\s*Corp\.?|\s*Ltd\.?', ''
                
                # Mencari produk di LiteDB menggunakan manipulasi PowerShell (case-insensitive)
                $matchedProduct = $collection.FindAll() | Where-Object {
                    $_["manufacturer"].AsString -match $cleanManufacturer -and
                    $_["product_name"].AsString -match [regex]::Escape($hwInfo.Model)
                } | Select-Object -First 1

                if ($matchedProduct) {
                    $epeatStatus = $matchedProduct["tier"].AsString
                }
                
                $db.Dispose()
            } else {
                Write-Host "[-] LiteDB.dll tidak ditemukan. Lewati pengecekan EPEAT." -ForegroundColor Yellow
            }
        } else {
            Write-Host "[-] sustainability.db tidak ditemukan. Lewati pengecekan EPEAT." -ForegroundColor Yellow
        }
        
        # KONSOLIDASI & TAMPILKAN HASIL KHUSUS WINDOWS
        $activeRemoteSessions = @($sessions | Where-Object { $_.IsRemote -eq $true })
        $remoteSessionData = [PSCustomObject]@{
            OSPlatform         = "Windows"
            HardwareModel      = $hardwareModel
            EpeatStatus        = $epeatStatus 
            Status             = if ($activeRemoteSessions.Count -gt 0) { "FAIL" } else { "PASS" }
            TotalSessions      = $sessions.Count
            RemoteSessionCount = $activeRemoteSessions.Count
            Details            = $sessions
        }
        
    }
    
    # ==========================================
    # 2. LINUX & MACOS: Menggunakan perintah 'who'
    # ==========================================
    elseif ($IsLinux -or $IsMacOS) {
        $osName = if ($IsLinux) { "LINUX" } else { "MACOS" }
        
        $whoOutput = who 2>$null
        
        if ($whoOutput) {
            foreach ($line in $whoOutput) {
                if ($line -match "^(\S+)\s+(\S+)\s+(.*?)\s*(?:\((.*?)\))?$") {
                    $username   = $matches[1]
                    $tty        = $matches[2]
                    $remoteHost = $matches[4]
                    
                    if ($null -ne $remoteHost) {
                        $remoteHost = $remoteHost.Trim()
                    }

                    if ([string]::IsNullOrWhiteSpace($remoteHost) -or $remoteHost -match "^:\d" -or $remoteHost -match "wayland|tty") {
                        $isRemote = $false
                        $finalRemoteHost = "localhost"
                    } else {
                        $isRemote = $true
                        $finalRemoteHost = $remoteHost
                    }
                    
                    $sessions += [PSCustomObject]@{
                        Username    = $username
                        SessionType = if ($isRemote) { "Remote ($tty)" } else { "Local ($tty)" }
                        RemoteHost  = $finalRemoteHost
                        IsRemote    = $isRemote
                        State       = "Active"
                    }
                }
            }
        }

        # Dapatkan Model Hardware Linux/MacOS dasar (Placeholder, jika ingin diperluas)
        $hardwareModel = "N/A (Cek DMI/dmidecode)"
        
        # KONSOLIDASI & TAMPILKAN HASIL KHUSUS LINUX/MACOS
        $activeRemoteSessions = @($sessions | Where-Object { $_.IsRemote -eq $true })
        $remoteSessionData = [PSCustomObject]@{
            OSPlatform         = $osName
            HardwareModel      = $hardwareModel
            EpeatStatus        = "Unregistered" 
            Status             = if ($activeRemoteSessions.Count -gt 0) { "FAIL" } else { "PASS" }
            TotalSessions      = $sessions.Count
            RemoteSessionCount = $activeRemoteSessions.Count
            Details            = $sessions
        }
    }

    # ==========================================
    # 3. CETAK KE LAYAR (UI REPORTING)
    # ==========================================
    if ($null -ne$remoteSessionData) {
        
        # [BARU] Menyusun format string untuk ActiveSessionsDetail berdasarkan Alternatif 2
        $formattedSessions = ""
        
        if ($remoteSessionData.Details.Count -gt 0) {$tempList = @()
            foreach ($sessionItem in $remoteSessionData.Details) {$tempList += "`n                         - $($sessionItem.Username) | Type: $($sessionItem.SessionType) | Host: $($sessionItem.RemoteHost) | IsRemote: $($sessionItem.IsRemote) | State: $($sessionItem.State)"
            }
            $formattedSessions = $tempList -join ""
        } else {
            $formattedSessions = "`n                         - Tidak ada sesi aktif yang terdeteksi."
        }

        # [DIUBAH] Membuat objek khusus untuk tampilan yang dicetak via Format-List
        $displayObject = [PSCustomObject]@{
            OS                   = $remoteSessionData.OSPlatform
            Status               = $remoteSessionData.Status
            HardwareModel        = $remoteSessionData.HardwareModel
            EPEATStatus          = $remoteSessionData.EpeatStatus
            TotalSessions        = $remoteSessionData.TotalSessions
            RemoteSessionsRDP    = $remoteSessionData.RemoteSessionCount
            ActiveSessionsDetail = $formattedSessions
        }

        # [DIUBAH] Cetak ke layar menggunakan Format-List (Key-Value style)
        $displayObject | Format-List | Out-String | Write-Host
        
        # [PERTAHANKAN] Objek data asli tetap direturn agar bisa ditangkap oleh ConvertTo-Json atau -auditendpoint
        return $remoteSessionData
    }
}