function controlCheckingRemoteSession{
    $osPlatform = if ($IsWindows) { "Windows" } elseif ($IsLinux) { "Linux" } else { "macOS" }
    Write-Host "`n[$osPlatform] Checking Remote Session & Sustainability Status..." @Net
    
    $databasePath = "$PSScriptRoot/../../Database"
    $libPath = "$PSScriptRoot/../../Helpers/Lib"
    
    $dbFile = Join-Path -Path $databasePath -ChildPath "sustainability.db"
    $liteDbDll = Join-Path -Path $libPath -ChildPath "LiteDB.dll"

    $sessions = @()
    $sysManufacturer = ""
    $sysModel = ""
    $hardwareModel = "Unknown"

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

        $hwInfo = Get-CimInstance Win32_ComputerSystem
        #$hwInfo = [PSCustomObject]@{ Manufacturer = "Dell Inc."; Model = "OptiPlex 3000" }
        $hardwareModel = "$($hwInfo.Manufacturer) $($hwInfo.Model)"
        
        $epeatStatus = "Unregistered"
        
        if (Test-Path $dbFile) {
            if (Test-Path $liteDbDll) {
                Add-Type -Path $liteDbDll
                $db = New-Object LiteDB.LiteDatabase("Filename=$dbFile;Connection=shared")
                $collection = $db.GetCollection("epeat_products")
                
                $cleanManufacturer = $hwInfo.Manufacturer -replace '(?i)\s*Inc\.?|\s*Corp\.?|\s*Ltd\.?', ''
                
                $matchedProduct = $collection.FindAll() | Where-Object {
                    $_["manufacturer"].AsString -match $cleanManufacturer -and
                    $_["product_name"].AsString -match [regex]::Escape($hwInfo.Model)
                } | Select-Object -First 1

                if ($matchedProduct) {
                    $epeatStatus = $matchedProduct["tier"].AsString
                }
                
                $db.Dispose()
            } else {
                Write-Host "[-] LiteDB.dll not found. Skip EPEAT checking." $Cha
            }
        } else {
            Write-Host "[-] sustainability.db not found. Skip EPEAT checking." $Cha
        }
        
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
    
    elseif ($IsLinux -or $IsMacOS) {
        $whoOutput = who 2>$null
        
        if ($whoOutput) {
            foreach ($line in $whoOutput) {
                if ($line -match "^(\S+)\s+(\S+)\s+(.*?)\s*(?:\((.*?)\))?$") {
                    $username   =$matches[1]
                    $tty        =$matches[2]
                    $remoteHost =$matches[4]
                    
                    if ($null -ne$remoteHost) {
                        $remoteHost =$remoteHost.Trim()
                    }

                    if ([string]::IsNullOrWhiteSpace($remoteHost) -or $remoteHost -match "^:\d" -or $remoteHost -match "wayland|tty") {
                        $isRemote = $false
                        $finalRemoteHost = "localhost"
                    } else {
                        $isRemote =$true
                        $finalRemoteHost =$remoteHost
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

        if ($IsLinux) {
            # PERBAIKAN: Membaca DMI via sysfs tanpa butuh akses sudo/root
            $sysVendorFile = "/sys/devices/virtual/dmi/id/sys_vendor"
            $sysProductFile = "/sys/devices/virtual/dmi/id/product_name"
            if (Test-Path $sysVendorFile) { $sysManufacturer = (Get-Content $sysVendorFile -ErrorAction SilentlyContinue).Trim() }
            if (Test-Path $sysProductFile) { $sysModel = (Get-Content $sysProductFile -ErrorAction SilentlyContinue).Trim() }
            
            if ($sysManufacturer -or $sysModel) {$hardwareModel = "$sysManufacturer$sysModel".Trim()
            } else {
                $hardwareModel = "Generic Linux Device"
            }
        } 
        elseif ($IsMacOS) {
            if (Get-Command sysctl -ErrorAction SilentlyContinue) {
                $sysModel = (sysctl -n hw.model 2>/dev/null).Trim()
            }
            $sysManufacturer = "Apple"
            if (-not $sysModel) {$sysModel = "Mac" }
            $hardwareModel = "$sysManufacturer$sysModel".Trim()
        }
    }

    $epeatStatus = "Unregistered"
    if ($sysManufacturer -and$sysModel) {
        if (Test-Path $dbFile) {
            if (Test-Path $liteDbDll) {
                try {
                    Add-Type -Path $liteDbDll
                    $db = New-Object LiteDB.LiteDatabase("Filename=$dbFile;Connection=shared")
                    $collection =$db.GetCollection("epeat_products")
                    
                    $cleanManufacturer =$sysManufacturer -replace '(?i)\s*Inc\.?|\s*Corp\.?|\s*Ltd\.?', ''
                    
                    $matchedProduct =$collection.FindAll() | Where-Object {
                        $_["manufacturer"].AsString -match $cleanManufacturer -and
                        $_["product_name"].AsString -match [regex]::Escape($sysModel)
                    } | Select-Object -First 1

                    if ($matchedProduct) {
                        $epeatStatus =$matchedProduct["tier"].AsString
                    }
                    $db.Dispose()
                } catch {
                    Write-Warning "Gagal membaca database EPEAT: $($_.Exception.Message)"
                }
            } else {
                Write-Host "[-] LiteDB.dll tidak ditemukan. Skip EPEAT checking." -ForegroundColor Yellow
            }
        } else {
            Write-Host "[-] sustainability.db tidak ditemukan. Skip EPEAT checking." -ForegroundColor Yellow
        }
    }

    $activeRemoteSessions = @($sessions | Where-Object { $_.IsRemote -eq$true })
    $status = if ($activeRemoteSessions.Count -gt 0) { "FAIL" } else { "PASS" }

    $formattedSessions = ""
    if ($sessions.Count -gt 0) {$tempList = @()
        foreach ($s in $sessions) {$tempList += "`n- $($s.Username) | $($s.SessionType) | $($s.RemoteHost) | Remote $($s.IsRemote) | $($s.State)"
        }
        $formattedSessions = $tempList -join ""
    } else {
        $formattedSessions = "`n- No active session detected."
    }

    $remoteSessionData = [PSCustomObject]@{
        OSPlatform           = $osPlatform
        Status               = $status
        HardwareModel        = $hardwareModel
        EpeatStatus          = $epeatStatus 
        TotalSessions        = $sessions.Count
        RemoteSessionCount   = $activeRemoteSessions.Count
        ActiveSessionsDetail = $formattedSessions
    }
    
    return $remoteSessionData
}
