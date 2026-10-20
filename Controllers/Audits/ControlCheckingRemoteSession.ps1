function controlCheckingRemoteSession{
    Write-Host "`n[Windows] Checking Remote Session & Sustainability Status..." @Net
    
    $databasePath = "$PSScriptRoot\..\..\Database"
    $libPath = "$PSScriptRoot\..\..\Helpers\Lib"
    $dbFile = "$databasePath\sustainability.db"
    $liteDbDll = "$libPath\LiteDB.dll"

    $sessions = @()
    $remoteSessionData = $null

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

        $hardwareModel = "N/A (Cek DMI/dmidecode)"
        
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

    if ($null -ne $remoteSessionData) {
        
        $formattedSessions = ""
        
        if ($remoteSessionData.Details.Count -gt 0) {$tempList = @()
            foreach ($sessionItem in $remoteSessionData.Details) {$tempList += "`n- $($sessionItem.Username) | $($sessionItem.SessionType) | $($sessionItem.RemoteHost) | Remote $($sessionItem.IsRemote) | $($sessionItem.State)"
            }
            $formattedSessions = $tempList -join ""
        } else {
            $formattedSessions = "`n- No active session detected."
        }

        $displayObject = [PSCustomObject]@{
            OS                   = $remoteSessionData.OSPlatform
            Status               = $remoteSessionData.Status
            HardwareModel        = $remoteSessionData.HardwareModel
            EPEATStatus          = $remoteSessionData.EpeatStatus
            TotalSessions        = $remoteSessionData.TotalSessions
            RemoteSessionsRDP    = $remoteSessionData.RemoteSessionCount
            ActiveSessionsDetail = $formattedSessions
        }

        $displayObject | Format-List | Out-String | Write-Host
        
        return $remoteSessionData
    }
}