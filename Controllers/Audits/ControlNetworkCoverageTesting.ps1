function controlNetworkCoverageTesting{
    $inboundPorts = @()
    $outboundConns = @()
    $osPlatform = if ($IsWindows) { "Windows" } elseif ($IsLinux) { "Linux" } else { "macOS" }
    
    Write-Host "`n[$osPlatform] Testing Signal Quality, Coverage & Outbound Sockets..." @Net

    $coverageStatus = "CRITICAL"
    $interfaceType  = "Unknown"
    $signalOrSpeed  = "Unknown"
    $latencyStr     = "Timeout"
    $coverageTier   = "BASIC"
    $latencyAvg     = 999

    if ($IsWindows) {
        try {
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

                $interfaceType = "Ethernet"
                $isWiFi = ($adapter.PhysicalMediaType -eq 802.11 -or $adapter.Name -match "Wi-Fi|Wireless")
                if ($isWiFi) { $interfaceType = "Wi-Fi" }

                $rssi = -100
                if ($isWiFi) {
                    $netsh = netsh wlan show interfaces
                    
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

                if ($isWiFi -and $signalOrSpeed -eq "Disconnected") {
                    $coverageTier   = "BASIC"
                    $coverageStatus = "CRITICAL"
                } elseif ($isWiFi -and $rssi -gt -100) {
                    if ($rssi -ge -60 -and $latencyAvg -lt 15) { $coverageTier = "MISSION-CRITICAL"; $coverageStatus = "OK" }
                    elseif ($rssi -ge -72 -and $latencyAvg -lt 30) { $coverageTier = "MULTIMEDIA"; $coverageStatus = "OK" }
                    elseif ($rssi -ge -80 -and $latencyAvg -lt 80) { $coverageTier = "PRODUCTIVITY"; $coverageStatus = "WARNING" }
                    else { $coverageTier = "BASIC"; $coverageStatus = "CRITICAL" }
                } else {
                    if ($latencyAvg -lt 10) { $coverageTier = "MISSION-CRITICAL"; $coverageStatus = "OK" }
                    elseif ($latencyAvg -lt 25) { $coverageTier = "MULTIMEDIA"; $coverageStatus = "OK" }
                    elseif ($latencyAvg -lt 50) { $coverageTier = "PRODUCTIVITY"; $coverageStatus = "WARNING" }
                    else { $coverageTier = "BASIC"; $coverageStatus = "CRITICAL" }
                }
            }
        } catch {
            Write-Warning "Failed to test Network Coverage: $($_.Exception.Message)"
        }
    }

    elseif ($IsLinux) {
        try {
            $defaultRoute = ip -4 route show default 2>/dev/null | Select-Object -First 1
            if ($defaultRoute -match 'default via (\S+) dev (\S+)') {
                $gateway =$matches[1]
                $iface =$matches[2]
                
                $isWiFi = ($iface -match '^wl')
                $interfaceType = if ($isWiFi) { "Wi-Fi" } else { "Ethernet" }
                
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

                if ($latencyAvg -lt 15) { $coverageTier = "MISSION-CRITICAL"; $coverageStatus = "OK" }
                elseif ($latencyAvg -lt 30) { $coverageTier = "MULTIMEDIA"; $coverageStatus = "OK" }
                elseif ($latencyAvg -lt 80) { $coverageTier = "PRODUCTIVITY"; $coverageStatus = "WARNING" }
                else { $coverageTier = "BASIC"; $coverageStatus = "CRITICAL" }

            } else {
                $coverageStatus = "CRITICAL"
                $signalOrSpeed  = "Disconnected / No Route"
            }
        } catch {
            Write-Warning "Failed to read Network Coverage Linux: $($_.Exception.Message)"
        }
    }

    if ($IsWindows) {
        try {
            $listenConns = Get-NetTCPConnection -State Listen -ErrorAction Stop
            $inboundPorts = $listenConns.LocalPort | Select-Object -Unique | Sort-Object

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

    elseif ($IsLinux) {
        if (Get-Command ss -ErrorAction SilentlyContinue) {
            $linesListen = ss -tln 2>/dev/null | Select-String "LISTEN"
            foreach ($line in $linesListen) {
                if ($line -match ":(\d+)\s+") {
                    $inboundPorts += [int]$Matches[1]
                }
            }

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
            Write-Warning "The 'ss' utility is not found on this Linux system."
        }
    }

    elseif ($IsMacOS) {     
        if (Get-Command lsof -ErrorAction SilentlyContinue) {
            $linesListen = lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null
            foreach ($line in $linesListen) {
                if ($line -match ":(\d+)\s+\(LISTEN") {
                    $inboundPorts += [int]$Matches[1]
                }
            }

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
            Write-Warning "The 'lsof' utility is not found in this macOS system."
        }
    }

    $inboundPorts = $inboundPorts | Select-Object -Unique | Sort-Object | Where-Object {$_ -ne $null }
    $portList = if ($inboundPorts) {$inboundPorts -join ", " } else { "None" }

    $auditStatus = "PASS"
    if ($outboundConns.Count -gt 50 -or $inboundPorts.Count -gt 15) {$auditStatus = "WARNING" }
    if ($coverageStatus -eq "POOR" -or $coverageStatus -eq "CRITICAL") { $auditStatus = "WARNING" }

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
        
        "`n- $procName (PID: $allPids) | $statusTag : $socketCount Sockets"
    }

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