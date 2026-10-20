function controlNetworkPerimeterTesting{
    $osName = "Unknown"
    $fwType = "Unknown"
    $fwStatus = $null
    $fwMessage = ""
    
    $roamingActive = $false
    $roamingMessage = "Tidak ada koneksi jaringan aktif."
    $bssid = "N/A"
    $ssid = "N/A (Ethernet Connection)"
    $signalPercent = "N/A"
    $rssi = "N/A"
    $avgLatency = -1
    $packetLoss = 100

    $egressTag = "N/A"
    $dnsTag    = "N/A"
    $mtuTag    = "N/A"
    $gwIP      = $null

    if ($IsWindows) {
        $osName = "Windows"
        $fwType = "Windows Defender Firewall"
        Write-Host "[Windows] Checking Firewall, Signal Quality & Roaming Perimeter..." @Net
        
        try {
            $profiles = Get-NetFirewallProfile -ErrorAction Stop
            $disabledProfiles = $profiles | Where-Object { $_.Enabled -eq $false -or $_.Enabled -eq 2 -or $_.Enabled -match "False" }
            
            if ($disabledProfiles.Count -eq 0) {
                $fwStatus = $true; $fwMessage = "All Firewall profiles are active."
            } else {
                $fwStatus = $false; $names = ($disabledProfiles.Name) -join ", "
                $fwMessage = "Profil Firewall OFF: $names."
            }
        }
        catch {
            $netshStatus = netsh advfirewall show allprofiles state 2>&1 | Out-String
            if ($netshStatus -match "State\s+OFF") { $fwStatus = $false; $fwMessage = "There is a Firewall profile in the OFF state." }
            elseif ($netshStatus -match "State\s+ON") { $fwStatus = $true; $fwMessage = "Windows Firewall is active." }
            else { $fwStatus = $null; $fwMessage = "Firewall status cannot be ascertained (Access Denied)." }
        }

        try {
            $wifiAdapter = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { 
                $_.Status -eq "Up" -and ($_.InterfaceDescription -match "Wireless|Wi-Fi|802.11" -or $_.Name -match "Wi-Fi") 
            }

            if ($wifiAdapter) {
                $roamingActive = $true
                $netProfile = Get-NetConnectionProfile -InterfaceAlias $wifiAdapter.Name -ErrorAction SilentlyContinue
                if (-not $netProfile) {
                    $netProfile = Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { $_.IPv4Connectivity -match "Internet|LocalNetwork" } | Select-Object -First 1
                }
                if ($netProfile) { $ssid = $netProfile.Name }

                $wlanRaw = netsh wlan show interfaces 2>&1 | Out-String
                
                if ($wlanRaw -match "Location permission" -or $wlanRaw -match "error 5") {
                    $bssid = "Requires Admin / Location Perm"
                    $signalPercent = "N/A"
                    $rssi = "N/A"
                } else {
                    $wlanLines =$wlanRaw -split "`r`n"
                    foreach ($line in $wlanLines) {
                        if ($line -match 'BSSID\s*:\s*([a-fA-F0-9:\-]{17})') { $bssid =$matches[1].Trim() }
                        if ($line -match '(?:Signal|Sinyal)\s*:\s*(\d+)%') { 
                            $signalPercent = [int]$matches[1]
                            $rssi = [math]::Round(($signalPercent / 2) - 100)
                        }
                    }
                }

                $gateway = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1
                if ($gateway) {
                    $gwIP = $gateway.IPv4DefaultGateway.NextHop
                    $pingResult = Test-Connection -ComputerName $gwIP -Count 3 -ErrorAction SilentlyContinue
                    if ($pingResult) {
                        $packetLoss = [math]::Round(((3 - $pingResult.Count) / 3) * 100)
                        
                        $times = $pingResult | ForEach-Object { if ($null -ne $_.ResponseTime) { $_.ResponseTime } elseif ($null -ne $_.Latency) { $_.Latency } }
                        if ($times) { $avgLatency = [math]::Round(($times | Measure-Object -Average).Average) }
                    }

                    try {
                        $tcpClient = New-Object System.Net.Sockets.TcpClient
                        $asyncResult = $tcpClient.BeginConnect("1.1.1.1", 445, $null, $null)
                        $wait = $asyncResult.AsyncWaitHandle.WaitOne(1000,$false) # Timeout 1 detik
                        if ($tcpClient.Connected) {$egressTag = "PERMISSIVE (High-Risk Ports Open)"
                            $tcpClient.Close()
                        } else {
                            $egressTag = "RESTRICTED (Port 445/SMB Blocked)"
                        }
                    } catch {
                        $egressTag = "RESTRICTED (Port 445/SMB Blocked)"
                    }

                    try {
                        $dnsTest = Resolve-DnsName -Name "one.one.one.one" -Server "1.1.1.1" -TcpOnly -ErrorAction SilentlyContinue
                        if ($dnsTest) {$dnsTag = "CLEAN (Public Resolver Valid)"
                        } else {
                            $dnsTag = "SUSPICIOUS (DNS Intercepted)"
                        }
                    } catch {
                        $dnsTag = "SUSPICIOUS (DNS Intercepted)"
                    }

                    $ping1500 = ping.exe -f -n 1 -w 1000 -l 1472 $gwIP 2>&1 | Out-String
                    if ($ping1500 -match "Reply from|Balasan dari") {
                        $mtuTag = "1500 Bytes"
                    } else {
                        $ping1420 = ping.exe -f -n 1 -w 1000 -l 1392 $gwIP 2>&1 | Out-String
                        if ($ping1420 -match "Reply from|Balasan dari") {
                            $mtuTag = "1420 Bytes (MTU Bottleneck)"
                        } else {
                            $mtuTag = "< 1420 Bytes (Fragmented / ICMP Blocked)"
                        }
                    }

                }

                $signalMsg = "Sinyal: $signalPercent% ($rssi dBm), Latency GW: $($avgLatency)ms, Loss: $($packetLoss)%"
                if ($bssid -ne "") {
                    $roamingMessage = "Wi-Fi Active | SSID: $ssid | BSSID: $bssid | $signalMsg"
                } elseif ($ssid -ne "") {
                    $roamingMessage = "Wi-Fi Active | SSID: $ssid (BSSID hidden) | $signalMsg"
                } else {
                    $roamingMessage = "Wi-Fi Active ($($wifiAdapter.InterfaceDescription)) | $signalMsg"
                }
            } else {
                $roamingActive = $false
                $roamingMessage = "No Wi-Fi connection is active."
            }
        } catch {
            $roamingMessage = "Failed to read Roaming/Wi-Fi metrics: $($_.Exception.Message)"
        }
        $gateway = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object {$_.IPv4DefaultGateway } | Select-Object -First 1
        if ($gateway) { 
            $gwIP = $gateway.IPv4DefaultGateway.NextHop
            if (-not $roamingActive) {$roamingMessage = "Active LAN Connection ($gwIP)"
            } else {
                $roamingMessage = "Wi-Fi Aktif | SSID: $ssid | BSSID: $bssid | Sinyal: $signalPercent\% ($rssi dBm)"
            }
        }
    }

    elseif ($IsLinux) {
        $osName = "Linux"
        Write-Host "[Linux] Testing UFW/Firewalld status..." @Net
        $fwStatus = $false 
        $fwMessage = "Firewall service not detected."

        if (Get-Command ufw -ErrorAction SilentlyContinue) { 
            $ufwState = ufw status 2>&1 | Out-String
            if ($ufwState -match "active") { $fwStatus =$true; $fwType = "UFW"; $fwMessage = "UFW Active." }
        } elseif (Get-Command firewall-cmd -ErrorAction SilentlyContinue) {
            $fwdState = firewall-cmd --state 2>&1 | Out-String
            if ($fwdState -match "running") { $fwStatus =$true; $fwType = "Firewalld"; $fwMessage = "Firewalld Active." }
        }

        $defaultRoute = ip -4 route show default 2>/dev/null | Select-Object -First 1
        if ($defaultRoute -match 'default via (\S+)') { 
            $gwIP = $matches[1]
            if (-not $roamingActive) {
                $roamingMessage = "Active LAN Connection ($gwIP)"
            }
        }
    }

    elseif ($IsMacOS) {
        $osName = "macOS"
        Write-Host "[macOS] Testing the Application Layer Firewall..." @Net
        $fwStatus = $false; $fwMessage = "ALF is not detected."
        
        if (Test-Path "/usr/libexec/ApplicationFirewall/socketfilterfw") {
            $alfState = /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>&1 | Out-String
            if ($alfState -match "enabled") { $fwStatus = $true; $fwMessage = "macOS ALF Active." }
            else { $fwStatus = $false; $fwMessage = "macOS ALF Disabled." }
        }

        $defaultRoute = route -n get default 2>/dev/null | Out-String
        if ($defaultRoute -match 'gateway:\s*(\S+)') {
            $gwIP = $matches[1]
            $roamingMessage = "Active Connection ($gwIP)"
        }
    }

    if ($gwIP) {
        $pingResult = Test-Connection -ComputerName $gwIP -Count 3 -ErrorAction SilentlyContinue
        if ($pingResult) {
            $packetLoss = [math]::Round(((3 - $pingResult.Count) / 3) * 100)
            $times =$pingResult | ForEach-Object { if ($null -ne$_.ResponseTime) { $_.ResponseTime } elseif ($null -ne $_.Latency) {$_.Latency } }
            if ($times) { $avgLatency = [math]::Round(($times | Measure-Object -Average).Average) }
        }

        try {
            $tcpClient = New-Object System.Net.Sockets.TcpClient
            $asyncResult = $tcpClient.BeginConnect("1.1.1.1", 445, $null, $null)
            $wait = $asyncResult.AsyncWaitHandle.WaitOne(1000,$false)
            if ($tcpClient.Connected) {$egressTag = "PERMISSIVE (High-Risk Ports Open)"
                $tcpClient.Close()
            } else {
                $egressTag = "RESTRICTED (Port 445/SMB Blocked)"
            }
        } catch {
            $egressTag = "RESTRICTED (Port 445/SMB Blocked)"
        }

        try {
            if ($IsWindows) {$dnsTest = Resolve-DnsName -Name "one.one.one.one" -Server "1.1.1.1" -TcpOnly -ErrorAction SilentlyContinue
                if ($dnsTest) { $dnsTag = "CLEAN (Public Resolver Valid)" } else { $dnsTag = "SUSPICIOUS (Possible Corporate DNS Intercepted)" }
            } else {
                if (Get-Command dig -ErrorAction SilentlyContinue) {
                    $dnsTest = dig '@1.1.1.1' one.one.one.one +tcp +short 2>/dev/null
                    if ($dnsTest -match "\d+\.\d+\.\d+\.\d+") { $dnsTag = "CLEAN (Public Resolver Valid)" } else { $dnsTag = "SUSPICIOUS (DNS Intercepted)" }
                } else {
                    $dnsSocket = New-Object System.Net.Sockets.TcpClient
                    $asyncDns =$dnsSocket.BeginConnect("1.1.1.1", 53, $null,$null)
                    if ($asyncDns.AsyncWaitHandle.WaitOne(1000,$false) -and $dnsSocket.Connected) {$dnsTag = "CLEAN (Port 53 Direct Reachable)"
                        $dnsSocket.Close()
                    } else {
                        $dnsTag = "SUSPICIOUS (DNS Intercepted / Port 53 Blocked)"
                    }
                }
            }
        } catch {
            $dnsTag = "SUSPICIOUS (DNS Intercepted)"
        }

        try {
            if ($IsWindows) {
                $ping1500 = ping.exe -f -n 1 -w 1000 -l 1472 $gwIP 2>&1 | Out-String
                if ($ping1500 -match "Reply from|Balasan dari") { $mtuTag = "1500 Bytes" }
                else {
                    $ping1420 = ping.exe -f -n 1 -w 1000 -l 1392 $gwIP 2>&1 | Out-String
                    if ($ping1420 -match "Reply from|Balasan dari") { $mtuTag = "1420 Bytes (MTU Bottleneck)" }
                    else { $mtuTag = "< 1420 Bytes (Fragmented / ICMP Blocked)" }
                }
            } elseif ($IsLinux) {
                $ping1500 = ping -c 1 -M do -s 1472 -W 1 $gwIP 2>&1 | Out-String
                if ($ping1500 -match "bytes from") { $mtuTag = "1500 Bytes" }
                else {
                    $ping1420 = ping -c 1 -M do -s 1392 -W 1 $gwIP 2>&1 | Out-String
                    if ($ping1420 -match "bytes from") { $mtuTag = "1420 Bytes (MTU Bottleneck)" }
                    else { $mtuTag = "< 1420 Bytes (Fragmented / ICMP Blocked)" }
                }
            } elseif ($IsMacOS) {
                $ping1500 = ping -c 1 -D -s 1472 -W 1000 $gwIP 2>&1 | Out-String
                if ($ping1500 -match "bytes from") { $mtuTag = "1500 Bytes" }
                else {
                    $ping1420 = ping -c 1 -D -s 1392 -W 1000 $gwIP 2>&1 | Out-String
                    if ($ping1420 -match "bytes from") { $mtuTag = "1420 Bytes (MTU Bottleneck)" }
                    else { $mtuTag = "< 1420 Bytes (Fragmented / ICMP Blocked)" }
                }
            }
        } catch {
            $mtuTag = "Unknown"
        }
    } else {
        $roamingMessage += " [Offline / Gateway Not Found]"
    }

    $finalStatus = "OK"
    $statusReason = @()

    # Evaluasi Firewall
    if ($fwStatus -eq $false -or $null -eq $fwStatus) {
        $finalStatus = "WARNING"
        $statusReason += "Firewall OFF"
    }

    if ($roamingActive -and $rssi -ne "N/A" -and $rssi -lt -75 -and $rssi -ne 0) { 
        $finalStatus = "WARNING"
        $statusReason += "Very Weak Signal ($rssi dBm)"
    }

    if ($packetLoss -gt 0 -and $packetLoss -lt 100) {
        $finalStatus = "WARNING"
        $statusReason += "Packet Loss ($packetLoss%)"
    } elseif ($packetLoss -eq 100) {
        $finalStatus = "CRITICAL"
        $statusReason += "Offline / No Route"
    }

    if ($egressTag -match "PERMISSIVE") {
        $finalStatus = "WARNING"
        $statusReason += "Egress Port Open"
    }
    if ($dnsTag -match "SUSPICIOUS") {
        $finalStatus = "WARNING"
        $statusReason += "DNS Intercepted"
    }

    if ($statusReason.Count -gt 0) {
        $fwMessage = "$fwMessage [Isu: $($statusReason -join ', ')]"
    }

    return [PSCustomObject]@{
        OS                = $osName
        Status            = $finalStatus
        Firewall_Active   = $fwStatus
        Firewall_Type     = $fwType
        Roaming_Active    = $roamingActive
        SSID              = $ssid
        BSSID             = $bssid
        SignalPercent     = $signalPercent
        RSSI_dBm          = $rssi
        GatewayLatency_ms = $avgLatency
        PacketLossPercent = $packetLoss
        Egress_Filtering  = $egressTag
        DNS_Tampering     = $dnsTag
        Path_MTU          = $mtuTag
        Firewall_Details  = $fwMessage
        Roaming_Details   = $roamingMessage
    }
}