. $PSScriptRoot\..\..\Config\Windows.ps1

function controlCheckingNetworkConnection{
    Write-Host "`n[*] Memulai Audit Network, Coverage & Sockets..." -ForegroundColor Cyan

    # Inisialisasi variabel penampung
    $inboundPorts = @()
    $outboundConns = @()
    $osPlatform = if ($IsWindows) { "Windows" } elseif ($IsLinux) { "Linux" } else { "macOS" }

    # ==========================================
    # [BARU] 0. NETWORK COVERAGE & LATENCY AUDIT
    # ==========================================
    $coverageStatus = "N/A"
    $connectionType = "Unknown"
    $ssid = "N/A"
    $signalPercent = 0
    $rssiDbm = 0
    $gatewayLatency = -1

    if ($IsWindows) {
        try {
            Write-Host "[+] Memeriksa Kualitas Sinyal & Coverage..." -ForegroundColor Green
            # Cari adapter aktif
            $activeAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | Select-Object -First 1
            
            if ($activeAdapter) {
                $isWifi = $activeAdapter.MediaType -match "802\.11|Wireless" -or $activeAdapter.InterfaceDescription -match "Wi-Fi|Wireless"
                $connectionType = if ($isWifi) { "Wi-Fi" } else { "Ethernet" }

                if ($isWifi) {
                    $wlan = netsh wlan show interfaces
                    $ssidMatch = $wlan | Select-String '^\s*SSID\s*:\s*(.*)$'
                    $sigMatch  = $wlan | Select-String '^\s*Signal\s*:\s*(.*)$'
                    
                    if ($ssidMatch) { $ssid = $ssidMatch.Matches.Groups[1].Value.Trim() }
                    if ($sigMatch) { 
                        $signalPercent = [int]($sigMatch.Matches.Groups[1].Value.Trim() -replace '%','') 
                        $rssiDbm = ($signalPercent / 2) - 100
                        
                        if ($signalPercent -ge 70) { $coverageStatus = "EXCELLENT" }
                        elseif ($signalPercent -ge 50) { $coverageStatus = "FAIR" }
                        else { $coverageStatus = "POOR" }
                    }
                } else {
                    $signalPercent = 100
                    $coverageStatus = "EXCELLENT (Cable)"
                }

                # Cek Ping ke Default Gateway (Jika ada)
                $gateway = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty NextHop -First 1
                if ($gateway) {
                    $ping = Test-Connection -TargetName $gateway -Count 2 -ErrorAction SilentlyContinue
                    if ($ping) {
                        $gatewayLatency = [math]::Round(($ping | Measure-Object -Property Latency -Average).Average, 2)
                    }
                }
            }
        } catch {
            Write-Warning "Gagal memeriksa Network Coverage."
        }
    }

    # ==========================================
    # 1. WINDOWS: Menggunakan Get-NetTCPConnection
    # ==========================================
    if ($IsWindows) {
        Write-Host "[+] Menjalankan modul Socket Audit OS: WINDOWS" -ForegroundColor Green
        
        try {
            # --- A. Inbound / Listening Ports ---
            $listenConns = Get-NetTCPConnection -State Listen -ErrorAction Stop
            $inboundPorts = $listenConns.LocalPort | Select-Object -Unique | Sort-Object

            # --- B. Outbound / Established Connections ---
            $tcpConns = Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue
            foreach ($conn in $tcpConns) {
                if ($conn.RemoteAddress -notmatch '^127\.' -and $conn.RemoteAddress -ne '::1') {
                    $procName = "Unknown"
                    if ($conn.OwningProcess) {
                        $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                        if ($proc) { $procName = $proc.Name }
                    }
                    
                    $outboundConns += [PSCustomObject]@{
                        ProcessName   = $procName
                        PID           = $conn.OwningProcess
                        LocalAddress  = "$($conn.LocalAddress):$($conn.LocalPort)"
                        RemoteAddress = "$($conn.RemoteAddress):$($conn.RemotePort)"
                        State         = $conn.State
                    }
                }
            }
        } catch {
            Write-Warning "Gagal membaca koneksi Windows. Pastikan dijalankan sebagai Administrator."
        }
    }

    # ==========================================
    # 2. LINUX: Menggunakan utilitas 'ss'
    # ==========================================
    elseif ($IsLinux) {
        Write-Host "[+] Menjalankan modul Socket Audit OS: LINUX" -ForegroundColor Green
        
        if (Get-Command ss -ErrorAction SilentlyContinue) {
            # --- A. Inbound / Listening Ports ---
            $linesListen = ss -tln 2>/dev/null | Select-String "LISTEN"
            foreach ($line in $linesListen) {
                if ($line -match ":(\d+)\s+") {
                    $inboundPorts += [int]$Matches[1]
                }
            }

            # --- B. Outbound / Established Connections ---
            $ssOutput = ss -ntp state established 2>/dev/null
            foreach ($line in $ssOutput) {
                if ($line -match 'ESTAB\s+\d+\s+\d+\s+(\S+)\s+(\S+)') {
                    $local  = $matches[1]
                    $remote = $matches[2]
                    
                    if ($remote -notmatch '^127\.' -and $remote -notmatch '^\[?::1\]?:') {
                        $procName = "Unknown"
                        $pid      = "N/A"
                        
                        if ($line -match 'users:\(\("([^"]+)",pid=(\d+)') {
                            $procName = $matches[1]
                            $pid      = $matches[2]
                        }
                        
                        $outboundConns += [PSCustomObject]@{
                            ProcessName   = $procName
                            PID           = $pid
                            LocalAddress  = $local
                            RemoteAddress = $remote
                            State         = "Established"
                        }
                    }
                }
            }
        } else {
            Write-Warning "Utilitas 'ss' tidak ditemukan di sistem Linux ini."
        }
    }

    # ==========================================
    # 3. MACOS: Menggunakan utilitas 'lsof'
    # ==========================================
    elseif ($IsMacOS) {
        Write-Host "[+] Menjalankan modul Socket Audit OS: MACOS" -ForegroundColor Green
        
        if (Get-Command lsof -ErrorAction SilentlyContinue) {
            # --- A. Inbound / Listening Ports ---
            $linesListen = lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null
            foreach ($line in $linesListen) {
                if ($line -match ":(\d+)\s+\(LISTEN") {
                    $inboundPorts += [int]$Matches[1]
                }
            }

            # --- B. Outbound / Established Connections ---
            $lsofOutput = lsof -iTCP -sTCP:ESTABLISHED -n -P 2>/dev/null
            foreach ($line in $lsofOutput) {
                if ($line -match '^(\S+)\s+(\d+).*?TCP\s+(\S+)->(\S+)\s+\(ESTABLISHED\)') {
                    $procName = $matches[1]
                    $pid      = $matches[2]
                    $local    = $matches[3]
                    $remote   = $matches[4]
                    
                    if ($remote -notmatch '^127\.' -and $remote -notmatch '^\[?::1\]?:') {
                        $outboundConns += [PSCustomObject]@{
                            ProcessName   = $procName
                            PID           = $pid
                            LocalAddress  = $local
                            RemoteAddress = $remote
                            State         = "Established"
                        }
                    }
                }
            }
        } else {
            Write-Warning "Utilitas 'lsof' tidak ditemukan di sistem macOS ini."
        }
    }

    # ==========================================
    # 4. KONSOLIDASI & FORMAT OUTPUT
    # ==========================================
    $inboundPorts = $inboundPorts | Select-Object -Unique | Sort-Object | Where-Object { $_ -ne $null }
    $portList = if ($inboundPorts) { $inboundPorts -join ", " } else { "None" }

    # Status Keseluruhan mempertimbangkan Coverage dan Sockets
    $auditStatus = "PASS"
    if ($outboundConns.Count -gt 50 -or $inboundPorts.Count -gt 15) { $auditStatus = "WARNING" }
    if ($coverageStatus -eq "POOR") { $auditStatus = "WARNING" }

    $networkAuditResult = [PSCustomObject]@{
        OSPlatform               = $osPlatform
        Status                   = $auditStatus
        ConnectionType           = $connectionType
        CoverageStatus           = $coverageStatus
        SSID                     = $ssid
        SignalPercent            = $signalPercent
        RSSI_dBm                 = $rssiDbm
        GatewayLatency_ms        = $gatewayLatency
        ListeningPortsCount      = if ($inboundPorts) { $inboundPorts.Count } else { 0 }
        ListeningPorts           = $portList
        OutboundConnectionsCount = $outboundConns.Count
        OutboundDetails          = @($outboundConns)
    }

    #$networkAuditResult | ConvertTo-Json -Depth 4

    Write-Host "`n==================================================" -ForegroundColor Cyan
    Write-Host " [ RINGKASAN STATUS & COVERAGE ]" -ForegroundColor Yellow
    Write-Host "==================================================" -ForegroundColor Cyan
    
    # Menampilkan Tabel 1 dengan Header Singkat (Pilihan 1)
    $networkAuditResult | Select-Object `
        @{Name="STATUS"; Expression={$_.Status}},
        @{Name="OS"; Expression={$_.OSPlatform}},
        @{Name="TYPE"; Expression={$_.ConnectionType}},
        @{Name="COVERAGE"; Expression={$_.CoverageStatus}},
        @{Name="LATENCY"; Expression={"$($_.GatewayLatency_ms) ms"}},
        @{Name="PORTS"; Expression={$_.ListeningPortsCount}},
        @{Name="OUTBOUND"; Expression={$_.OutboundConnectionsCount}} | 
        Format-Table -AutoSize | Out-String | Write-Host

    Write-Host "==================================================" -ForegroundColor Cyan
    Write-Host " [ DETAIL KONEKSI OUTBOUND ($($networkAuditResult.OutboundConnectionsCount) Koneksi Aktif) ]" -ForegroundColor Yellow
    Write-Host "==================================================" -ForegroundColor Cyan
    
$aggregatedResults = foreach ($group in $networkAuditResult.OutboundDetails | Group-Object PID) {
    $pidNum = $group.Name
    $procName = $group.Group[0].ProcessName
    $socketCount = $group.Count
    
    # Nilai default
    $statusTag = "[UNKNOWN]"
    $publisher = "Unknown Publisher"
    $riskLevel = "LOW"
    
    # 1. Ambil detail proses aktif
    $proc = Get-Process -Id $pidNum -ErrorAction SilentlyContinue
    
    if ($proc -and $proc.Path) {
        # Jika PowerShell punya hak akses untuk membaca file
        $sig = Get-AuthenticodeSignature -FilePath $proc.Path -ErrorAction SilentlyContinue
        if ($sig -and $sig.Status -eq 'Valid') {
            $statusTag = "[VALID]"
        } else {
            $statusTag = "[UNSIGNED]"
            $riskLevel = "HIGH"
        }
        
        # Ekstrak nama perusahaan / publisher dari file
        $company = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($proc.Path).CompanyName
        if (-not [string]::IsNullOrWhiteSpace($company)) {
            $publisher = $company.Trim()
        }
        
        # Heuristik lokasi mencurigakan
        if ($proc.Path -match 'AppData\\Local\\Temp') {
            $statusTag = "[!] SUSPICIOUS"
            $riskLevel = "HIGH"
        }
    } else {
        # Jika proses tidak bisa dibaca (butuh hak akses Admin / SYSTEM)
        $statusTag = "[PROTECTED]"
        if ($pidNum -eq 4 -or $procName -match "System") {
            $publisher = "NT AUTHORITY / OS Core"
        } elseif ($procName -match "svchost") {
            $publisher = "Windows Core Service"
        } else {
            $publisher = "System Service (Admin Only)"
        }
    }
    
    # Heuristik ekstra untuk Living off the Land (LOLBins)
    if ($procName -match 'cmd|powershell|wscript|cscript|rundll32') {
        $riskLevel = "MEDIUM"
        if ($statusTag -eq '[UNSIGNED]') { $riskLevel = "HIGH" }
    }
    
    # Buat baris data
    [PSCustomObject]@{
        PROCESS = $procName
        PID     = $pidNum
        SOCKETS = $socketCount
        'PUBLISHER / STATUS' = "$statusTag $publisher"
        RISK    = $riskLevel
    }
}

    $aggregatedResults | Sort-Object PROCESS | Format-Table -AutoSize

}