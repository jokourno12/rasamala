. $PSScriptRoot\..\..\Config\Windows.ps1

function controlCheckingRemoteSession{
    Write-Host "`n[*] Memulai Audit Remote Session..." @Cha
    $sessions = @()

    # ==========================================
    # 1. WINDOWS: Menggunakan 'quser.exe'
    # ==========================================
    if ($IsWindows) {
        Write-Host "[+] Menjalankan modul OS: WINDOWS" @Net
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

        # KONSOLIDASI & TAMPILKAN HASIL KHUSUS WINDOWS
        $activeRemoteSessions = @($sessions | Where-Object { $_.IsRemote -eq $true })
        $auditResults['RemoteSession'] = [PSCustomObject]@{
            OSPlatform         = "Windows"
            Status             = if ($activeRemoteSessions.Count -gt 0) { "FAIL" } else { "PASS" }
            TotalSessions      = $sessions.Count
            RemoteSessionCount = $activeRemoteSessions.Count
            Details            = $sessions
        }
        
        # Cetak langsung ke layar
        $auditResults['RemoteSession'] | ConvertTo-Json -Depth 4
    }
    
    # ==========================================
    # 2. LINUX & MACOS: Menggunakan perintah 'who'
    # ==========================================
    elseif ($IsLinux -or $IsMacOS) {
        $osName = if ($IsLinux) { "LINUX" } else { "MACOS" }
        Write-Host "[+] Menjalankan modul OS: $osName" @Net
        
        $whoOutput = who 2>$null
        
        if ($whoOutput) {
            foreach ($line in $whoOutput) {
                if ($line -match "^(\S+)\s+(\S+)\s+(.*?)\s*(?:\((.*?)\))?$") {
                    $username   = $matches[1]
                    $tty        = $matches[2]
                    $remoteHost = $matches[4]
                    
                    $isRemote = -not [string]::IsNullOrWhiteSpace($remoteHost)
                    
                    $sessions += [PSCustomObject]@{
                        Username    = $username
                        SessionType = if ($isRemote) { "Remote ($tty)" } else { "Local ($tty)" }
                        RemoteHost  = if ($isRemote) { $remoteHost } else { "localhost" }
                        IsRemote    = $isRemote
                        State       = "Active"
                    }
                }
            }
        }

        # KONSOLIDASI & TAMPILKAN HASIL KHUSUS LINUX/MACOS
        $activeRemoteSessions = @($sessions | Where-Object { $_.IsRemote -eq $true })
        $auditResults['RemoteSession'] = [PSCustomObject]@{
            OSPlatform         = $osName
            Status             = if ($activeRemoteSessions.Count -gt 0) { "FAIL" } else { "PASS" }
            TotalSessions      = $sessions.Count
            RemoteSessionCount = $activeRemoteSessions.Count
            Details            = $sessions
        }
        
        # Cetak langsung ke layar
        $auditResults['RemoteSession'] | ConvertTo-Json -Depth 4
    }
}