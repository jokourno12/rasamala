function controlNetworkCoverageTesting{
    # Inisialisasi variabel penampung
    $inboundPorts = @()
    $outboundConns = @()
    $osPlatform = if ($IsWindows) { "Windows" } elseif ($IsLinux) { "Linux" } else { "macOS" }
    
    Write-Host "`n[$osPlatform] Memeriksa Kualitas Sinyal, Coverage & Outbound Sockets..." @Net

    # ==========================================
    # [BARU] 0. NETWORK COVERAGE & LATENCY AUDIT
    # ==========================================
    $coverageStatus = "CRITICAL"
    $interfaceType  = "Unknown"
    $signalOrSpeed  = "Unknown"
    $latencyStr     = "Timeout"
    $coverageTier   = "BASIC"
    $latencyAvg     = 999

    if ($IsWindows) {
        try {
            # Cari Default Gateway dan Adapter Jaringan aktif
            $routes = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Sort-Object RouteMetric
            $route = $null
            $adapter = $null
            
            foreach ($r in $routes) {
                $candAdapter = Get-NetAdapter -InterfaceIndex $r.ifIndex -ErrorAction SilentlyContinue
                if ($candAdapter -and $candAdapter.MediaConnectionState -ne "Disconnected") {
                    $route = $r
                    $adapter = $candAdapter
                    break
                }
            }

            if (-not $route -and $routes) {
                $route = $routes[0]
                $adapter = Get-NetAdapter -InterfaceIndex $route.ifIndex -ErrorAction SilentlyContinue
            }

            if ($route) {
                $gateway = $route.NextHop

                # Tentukan jenis antarmuka
                $interfaceType = "Ethernet"
                $isWiFi = ($adapter.PhysicalMediaType -eq 802.11 -or $adapter.Name -match "Wi-Fi|Wireless")
                if ($isWiFi) { $interfaceType = "Wi-Fi" }

                # Ukur Sinyal (Wi-Fi) atau Kecepatan (Ethernet / VPN)
                $rssi = -100
                if ($isWiFi) {
                    $netsh = netsh wlan show interfaces
                    
                    # [PERBAIKAN]: Tangkap pesan penolakan akses dari Windows
                    if ($netsh -match "error 5|requires elevation|location permission") {
                        if ($adapter -and $adapter.Speed) {
                            try {
                                $speedMbps = [math]::Round([uint64]$adapter.Speed / 1000000)
                                $signalOrSpeed = "$speedMbps Mbps (Need Admin)"
                            } catch {
                                $signalOrSpeed = "Need Admin"
                            }
                        } else {
                            $signalOrSpeed = "Need Admin"
                        }
                    } else {
                        $stateLine = $netsh | Select-String "State\s*:\s*(.*)"
                        if ($stateLine -and $stateLine.Matches.Groups[1].Value.Trim() -match "disconnected") {
                            $signalOrSpeed  = "Disconnected"
                            $coverageStatus = "CRITICAL"
                            $coverageTier   = "BASIC"
                        } else {
                            $sigLine = $netsh | Select-String "Signal|Sinyal" | Select-Object -First 1
                            if ($sigLine -and $sigLine.Line -match "(\d+)%") {
                                $sigPercent = [int]$matches[1]
                                $rssi = [math]::Round(($sigPercent / 2) - 100)
                                $sigLabel = if ($rssi -ge -60) { "Strong" } elseif ($rssi -ge -74) { "Moderate" } else { "Weak" }
                                $signalOrSpeed = "$rssi dBm ($sigLabel)"
                            } else {
                                $signalOrSpeed = "No Signal"
                            }
                        }
                    }
                } else {
                    # Logika Ethernet
                    if ($adapter -and $adapter.Speed) {
                        try {
                            $speedMbps = [math]::Round([uint64]$adapter.Speed / 1000000)
                            if ($speedMbps -ge 1000) {
                                $signalOrSpeed = "$($speedMbps / 1000) Gbps Link"
                            } else {
                                $signalOrSpeed = "$speedMbps Mbps Link"
                            }
                        } catch {
                            $signalOrSpeed = "Active Link"
                        }
                    } else {
                        $signalOrSpeed = "Unknown Speed"
                    }
                }

                # Pengujian Latensi Aktif (Ping Burst ke Gateway)
                $ping = Test-Connection -TargetName $gateway -Count 3 -ErrorAction SilentlyContinue
                if ($ping) {
                    $validPings = $ping | Where-Object { $_.ResponseTime -ne $null -or $_.Latency -ne $null }
                    if ($validPings) {
                        if ($validPings[0].ResponseTime -ne $null) {
                            $latencyAvg = ($validPings | Measure-Object -Property ResponseTime -Average).Average
                        } else {
                            $latencyAvg = ($validPings | Measure-Object -Property Latency -Average).Average
                        }
                        if ($latencyAvg -eq 0) { $latencyAvg = 0.5 }
                        $latencyStr = "{0:N1} ms" -f $latencyAvg
                    }
                }

                # Evaluasi TIER berdasarkan performa aktif
                if ($isWiFi -and $signalOrSpeed -eq "Disconnected") {
                    $coverageTier   = "BASIC"
                    $coverageStatus = "CRITICAL"
                } elseif ($isWiFi -and $rssi -gt -100) {
                    # Evaluasi Wi-Fi Presisi dengan Sinyal dBm (Jika Run as Admin)
                    if ($rssi -ge -60 -and $latencyAvg -lt 15) { $coverageTier = "MISSION-CRITICAL"; $coverageStatus = "OK" }
                    elseif ($rssi -ge -72 -and $latencyAvg -lt 30) { $coverageTier = "MULTIMEDIA"; $coverageStatus = "OK" }
                    elseif ($rssi -ge -80 -and $latencyAvg -lt 80) { $coverageTier = "PRODUCTIVITY"; $coverageStatus = "WARNING" }
                    else { $coverageTier = "BASIC"; $coverageStatus = "CRITICAL" }
                } else {
                    # Fallback untuk Ethernet atau Wi-Fi Non-Admin (Berbasis Latensi & Speed)
                    if ($latencyAvg -lt 10) { $coverageTier = "MISSION-CRITICAL"; $coverageStatus = "OK" }
                    elseif ($latencyAvg -lt 25) { $coverageTier = "MULTIMEDIA"; $coverageStatus = "OK" }
                    elseif ($latencyAvg -lt 50) { $coverageTier = "PRODUCTIVITY"; $coverageStatus = "WARNING" }
                    else { $coverageTier = "BASIC"; $coverageStatus = "CRITICAL" }
                }
            }
        } catch {
            Write-Warning "Gagal memeriksa Network Coverage: $($_.Exception.Message)"
        }
    }

    elseif ($IsLinux) {
        try {
            # Ambil Default Gateway dari tabel routing kernel Linux
            $defaultRoute = ip -4 route show default 2>/dev/null | Select-Object -First 1
            if ($defaultRoute -match 'default via (\S+) dev (\S+)') {
                $gateway =$matches[1]
                $iface =$matches[2]
                
                # Interface Wi-Fi di Linux biasanya berawalan 'wl' (wlan0, wlp2s0)
                $isWiFi = ($iface -match '^wl')
                $interfaceType = if ($isWiFi) { "Wi-Fi" } else { "Ethernet" }
                
                # Baca Sinyal/Kecepatan
                if ($isWiFi) {
                    $iwOutput = iwconfig$iface 2>/dev/null | Select-String "Signal level=(-\d+)\s+dBm"
                    if ($iwOutput -and $iwOutput.Matches.Groups[1].Value) {
                        $rssi = [int]$iwOutput.Matches.Groups[1].Value 
                        $sigLabel = if ($rssi -ge -60) { "Strong" } elseif ($rssi -ge -74) { "Moderate" } else { "Weak" }
                        $signalOrSpeed = "$rssi dBm ($sigLabel)"
                    } else {
                        $signalOrSpeed = "Active Wi-Fi Link"
                    }
                } else {
                    $speedFile = "/sys/class/net/$iface/speed"
                    if (Test-Path $speedFile) {
                        $speed = Get-Content$speedFile -ErrorAction SilentlyContinue
                        if ($speed -and$speed -ne "-1") {
                            $signalOrSpeed = "$speed Mbps Link"
                        } else {
                            $signalOrSpeed = "Active Link"
                        }
                    } else {
                        $signalOrSpeed = "Active Link"
                    }
                }

                # Pengujian Latensi Aktif (Ping ke Gateway)
                $ping = Test-Connection -TargetName$gateway -Count 3 -ErrorAction SilentlyContinue
                if ($ping) {
                    $validPings =$ping | Where-Object { $_.ResponseTime -ne$null -or $_.Latency -ne$null }
                    if ($validPings) {
                        if ($validPings[0].ResponseTime -ne$null) {
                            $latencyAvg = ($validPings | Measure-Object -Property ResponseTime -Average).Average
                        } else {
                            $latencyAvg = ($validPings | Measure-Object -Property Latency -Average).Average
                        }
                        if ($latencyAvg -eq 0) {$latencyAvg = 0.5 }
                        $latencyStr = "{0:N1} ms" -f $latencyAvg
                    }
                }

                # Evaluasi TIER
                if ($latencyAvg -lt 15) { $coverageTier = "MISSION-CRITICAL"; $coverageStatus = "OK" }
                elseif ($latencyAvg -lt 30) { $coverageTier = "MULTIMEDIA"; $coverageStatus = "OK" }
                elseif ($latencyAvg -lt 80) { $coverageTier = "PRODUCTIVITY"; $coverageStatus = "WARNING" }
                else { $coverageTier = "BASIC"; $coverageStatus = "CRITICAL" }

            } else {
                $coverageStatus = "CRITICAL"
                $signalOrSpeed  = "Disconnected / No Route"
            }
        } catch {
            Write-Warning "Gagal membaca Network Coverage Linux: $($_.Exception.Message)"
        }
    }

    # ==========================================
    # 1. WINDOWS: Menggunakan Get-NetTCPConnection
    # ==========================================
    if ($IsWindows) {
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
    $inboundPorts = $inboundPorts | Select-Object -Unique | Sort-Object | Where-Object {$_ -ne $null }
    $portList = if ($inboundPorts) {$inboundPorts -join ", " } else { "None" }

    # Status Keseluruhan mempertimbangkan Coverage dan Sockets
    $auditStatus = "PASS"
    if ($outboundConns.Count -gt 50 -or $inboundPorts.Count -gt 15) {$auditStatus = "WARNING" }
    if ($coverageStatus -eq "POOR" -or $coverageStatus -eq "CRITICAL") { $auditStatus = "WARNING" }

    # Eksekusi proses pengumpulan data untuk Outbound Sockets
    $aggregatedResults = foreach ($group in $outboundConns | Group-Object ProcessName) {
        $procName =$group.Name
        $allPids = ($group.Group.PID | Select-Object -Unique) -join ', '
        $socketCount =$group.Count
        $firstPid = $group.Group[0].PID
        $statusTag = "[UNKNOWN]"
        $publisher = "Unknown Publisher"
        $riskLevel = "LOW"
        
        $proc = Get-Process -Id $firstPid -ErrorAction SilentlyContinue
        
        if ($proc -and$proc.Path) {
            if ($IsWindows) {
                $sig = Get-AuthenticodeSignature -FilePath 	$proc.Path -ErrorAction SilentlyContinue
                if ($sig -and $sig.Status -eq 'Valid') {$statusTag = "[VALID]" }
                else { $statusTag = "[UNSIGNED]"; $riskLevel = "HIGH" }
                    
                $company = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($proc.Path).CompanyName
                if (-not [string]::IsNullOrWhiteSpace($company)) { $publisher =$company.Trim() }
            } 
            elseif ($IsLinux -or $IsMacOS) {
                if ($proc.Path -match '^/(usr/)?(s)?bin/' -or $proc.Path -match '^/lib') {
                    $statusTag = "[VALID]"; $publisher = "System / OS Core Binary"
                } else {
                    $statusTag = "[UNVERIFIED]"; $publisher = "User / Third-Party Binary"
                }
            }
            
            if ($proc.Path -match 'AppData\\Local\\Temp') {
                $statusTag = "[!] SUSPICIOUS"; $riskLevel = "HIGH"
            }
        } else {
            $statusTag = "[PROTECTED]"
            if ($firstPid -eq 4 -or $procName -match "System") { $publisher = "NT AUTHORITY / OS Core" }
            elseif ($procName -match "svchost") { $publisher = "Windows Core Service" }
            else { $publisher = "System Service (Admin Only)" }
        }
        
        "`n  - $procName (PID: $allPids) | $statusTag : $socketCount Sockets"
    }

    # [DIKEMBALIKAN KE STRUKTUR ASLI] agar tidak merusak format -auditendpoint
    $networkAuditResult = [PSCustomObject]@{
        OSPlatform               = $osPlatform
        Status                   = $auditStatus
        CoverageStatus           = $coverageStatus
        InterfaceType            = $interfaceType
        SignalOrSpeed            = $signalOrSpeed
        LatencyStr               = $latencyStr
        CoverageTier             = $coverageTier
        ListeningPortsCount      = if ($inboundPorts) { $inboundPorts.Count } else { 0 }
        ListeningPorts           = $portList
        OutboundConnectionsCount = $outboundConns.Count
        OutboundDetails          = @($outboundConns)
    }

    $networkAuditResult | Add-Member -NotePropertyName "AggregatedSockets" -NotePropertyValue $aggregatedResults

    # Cetak ke layar dengan format Key-Value (Opsi 2) tanpa memengaruhi objek aslinya
    $networkAuditResult | Select-Object `
        @{Name="OS"; Expression={$_.OSPlatform}},
        Status,
        @{Name="Interface"; Expression={$_.InterfaceType}},
        @{Name="LinkSpeed"; Expression={$_.SignalOrSpeed}},
        @{Name="Latency"; Expression={$_.LatencyStr}},
        @{Name="Coverage_Tested"; Expression={$_.CoverageTier}},
        @{Name="TotalOutboundSockets"; Expression={$_.OutboundConnectionsCount}},
        @{Name="TopSocketProcesses"; Expression={($_.AggregatedSockets | Sort-Object) -join ''}} | 
        Format-List | Out-String | Write-Host

    return $networkAuditResult
}