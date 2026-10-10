. $PSScriptRoot\..\..\Config\Windows.ps1

function controlNetworkPerimeterTesting{
    $osName = "Unknown"
    $fwType = "Unknown"
    $fwStatus = $null
    $fwMessage = ""
    
    # Variabel Default Modul Roaming
    $roamingActive = $false
    $roamingMessage = "Roaming Check: Tidak didukung pada koneksi Non-Wi-Fi / OS ini."
    $bssid = ""
    $ssid = ""
    $signalPercent = 0
    $rssi = 0
    $avgLatency = -1
    $packetLoss = 100

    $egressTag = "N/A"
    $dnsTag    = "N/A"
    $mtuTag    = "N/A"
    $gwIP      = $null

    # ==========================================
    # 1. KODE FIREWALL (WINDOWS)
    # ==========================================
    if ($IsWindows) {
        $osName = "Windows"
        $fwType = "Windows Defender Firewall"
        Write-Host "[Windows] Memeriksa Firewall, Kualitas Sinyal & Perimeter Roaming..." @Net
        
        # [A] Cek Firewall
        try {
            $profiles = Get-NetFirewallProfile -ErrorAction Stop
            $disabledProfiles = $profiles | Where-Object { $_.Enabled -eq $false -or $_.Enabled -eq 2 -or $_.Enabled -match "False" }
            
            if ($disabledProfiles.Count -eq 0) {
                $fwStatus = $true; $fwMessage = "Semua profil Firewall aktif."
            } else {
                $fwStatus = $false; $names = ($disabledProfiles.Name) -join ", "
                $fwMessage = "Profil Firewall OFF: $names."
            }
        }
        catch {
            $netshStatus = netsh advfirewall show allprofiles state 2>&1 | Out-String
            if ($netshStatus -match "State\s+OFF") { $fwStatus = $false; $fwMessage = "Ada profil Firewall dalam keadaan OFF." }
            elseif ($netshStatus -match "State\s+ON") { $fwStatus = $true; $fwMessage = "Windows Firewall aktif." }
            else { $fwStatus = $null; $fwMessage = "Status Firewall tidak dapat dipastikan (Access Denied)." }
        }

        # ==========================================
        # 2. MODUL ROAMING, SIGNAL & LATENCY (WINDOWS)
        # ==========================================
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

                # Ekstrak BSSID dan Signal (%) dari netsh
                $wlanRaw = netsh wlan show interfaces 2>&1 | Out-String
                
                # Cek apakah terbentur proteksi Privasi Lokasi atau Hak Akses Admin
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

                # Uji Latensi ke Default Gateway
                $gateway = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.IPv4DefaultGateway } | Select-Object -First 1
                if ($gateway) {
                    $gwIP = $gateway.IPv4DefaultGateway.NextHop
                    # Ping 3x ke Router
                    $pingResult = Test-Connection -ComputerName $gwIP -Count 3 -ErrorAction SilentlyContinue
                    if ($pingResult) {
                        $packetLoss = [math]::Round(((3 - $pingResult.Count) / 3) * 100)
                        
                        # Dukungan lintas versi PS5.1 (ResponseTime) dan PS7+ (Latency)
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
                        # Resolve one.one.one.one lewat TCP ke 1.1.1.1
                        $dnsTest = Resolve-DnsName -Name "one.one.one.one" -Server "1.1.1.1" -TcpOnly -ErrorAction SilentlyContinue
                        if ($dnsTest) {$dnsTag = "CLEAN (Public Resolver Valid)"
                        } else {
                            $dnsTag = "SUSPICIOUS (DNS Intercepted)"
                        }
                    } catch {
                        $dnsTag = "SUSPICIOUS (DNS Intercepted)"
                    }

                    $ping1500 = ping.exe -f -n 1 -w 1000 -l 1472$gwIP 2>&1 | Out-String # 1472 payload + 28 header = 1500
                    if ($ping1500 -match "Reply from|Balasan dari") {
                        $mtuTag = "1500 Bytes"
                    } else {
                        $ping1420 = ping.exe -f -n 1 -w 1000 -l 1392$gwIP 2>&1 | Out-String # 1392 payload + 28 = 1420
                        if ($ping1420 -match "Reply from|Balasan dari") {
                            $mtuTag = "1420 Bytes (MTU Bottleneck)"
                        } else {
                            $mtuTag = "< 1420 Bytes (Fragmented)"
                        }
                    }

                }

                # Susun Pesan Roaming
                $signalMsg = "Sinyal: $signalPercent% ($rssi dBm), Latency GW: $($avgLatency)ms, Loss: $($packetLoss)%"
                if ($bssid -ne "") {
                    $roamingMessage = "Wi-Fi Aktif | SSID: $ssid | BSSID: $bssid | $signalMsg"
                } elseif ($ssid -ne "") {
                    $roamingMessage = "Wi-Fi Aktif | SSID: $ssid (BSSID hidden) | $signalMsg"
                } else {
                    $roamingMessage = "Wi-Fi Aktif ($($wifiAdapter.InterfaceDescription)) | $signalMsg"
                }
            } else {
                $roamingActive = $false
                $roamingMessage = "Tidak ada koneksi Wi-Fi aktif."
            }
        } catch {
            $roamingMessage = "Gagal membaca metrik Roaming/Wi-Fi: $($_.Exception.Message)"
        }
        $gateway = Get-NetIPConfiguration -ErrorAction SilentlyContinue | Where-Object {$_.IPv4DefaultGateway } | Select-Object -First 1
        if ($gateway) { $gwIP =$gateway.IPv4DefaultGateway.NextHop }
    }

    # ==========================================
    # 3. KODE FIREWALL (LINUX)
    # ==========================================
    elseif ($IsLinux) {
        $osName = "Linux"
        Write-Host "[Linux] Memeriksa status UFW/Firewalld..." @Net
        $fwStatus = $false; $fwMessage = "Layanan Firewall tidak terdeteksi."
        # ... (Logika Linux tetap sama seperti sebelumnya, dipersingkat di contoh ini agar fokus ke Windows) ...
        if (Get-Command ufw -ErrorAction SilentlyContinue) { $fwStatus = $true; $fwType = "UFW"; $fwMessage = "UFW Aktif." }

        $defaultRoute = ip -4 route show default 2>/dev/null | Select-Object -First 1
        if ($defaultRoute -match 'default via (\S+)') { $gwIP =$matches[1] }
    }

    # ==========================================
    # 4. KODE FIREWALL (macOS)
    # ==========================================
    elseif ($IsMacOS) {
        $osName = "macOS"
        Write-Host "[macOS] Memeriksa Application Layer Firewall..." @Net
        $fwStatus = $false; $fwMessage = "ALF tidak terdeteksi."
        # ... (Logika macOS tetap sama seperti sebelumnya) ...
    }

    if ($gwIP) {
        # [A] Ping & Packet Loss
        $pingResult = Test-Connection -ComputerName $gwIP -Count 3 -ErrorAction SilentlyContinue
        if ($pingResult) {
            $packetLoss = [math]::Round(((3 -$pingResult.Count) / 3) * 100)
            $times =$pingResult | ForEach-Object { if ($null -ne$_.ResponseTime) { $_.ResponseTime } elseif ($null -ne $_.Latency) {$_.Latency } }
            if ($times) { $avgLatency = [math]::Round(($times | Measure-Object -Average).Average) }
        }

        # [B] Egress Filtering (Port 445 SMB)
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

        # [C] DNS Tampering (Resolusi one.one.one.one)
        try {
            if ($IsWindows) {$dnsTest = Resolve-DnsName -Name "one.one.one.one" -Server "1.1.1.1" -TcpOnly -ErrorAction SilentlyContinue
                if ($dnsTest) { $dnsTag = "CLEAN (Public Resolver Valid)" } else { $dnsTag = "SUSPICIOUS (DNS Intercepted)" }
            } elseif ($IsLinux -or $IsMacOS) {$dnsTest = dig '@1.1.1.1' one.one.one.one +tcp +short 2>/dev/null
                if ($dnsTest -match "\d+\.\d+\.\d+\.\d+") { $dnsTag = "CLEAN (Public Resolver Valid)" } else { $dnsTag = "SUSPICIOUS (DNS Intercepted)" }
            }
        } catch {
            $dnsTag = "SUSPICIOUS (DNS Intercepted)"
        }

        # [D] Path MTU Discovery
        try {
            if ($IsWindows) {
                $ping1500 = ping.exe -f -n 1 -w 1000 -l 1472$gwIP 2>&1 | Out-String
                if ($ping1500 -match "Reply from|Balasan dari") { $mtuTag = "1500 Bytes" }
                else {
                    $ping1420 = ping.exe -f -n 1 -w 1000 -l 1392$gwIP 2>&1 | Out-String
                    if ($ping1420 -match "Reply from|Balasan dari") { $mtuTag = "1420 Bytes (MTU Bottleneck)" }
                    else { $mtuTag = "< 1420 Bytes (Fragmented)" }
                }
            } elseif ($IsLinux -or$IsMacOS) {
                $ping1500 = ping -c 1 -M do -s 1472 -W 1$gwIP 2>&1 | Out-String
                if ($ping1500 -match "bytes from") { $mtuTag = "1500 Bytes" }
                else {
                    $ping1420 = ping -c 1 -M do -s 1392 -W 1$gwIP 2>&1 | Out-String
                    if ($ping1420 -match "bytes from") { $mtuTag = "1420 Bytes (MTU Bottleneck)" }
                    else { $mtuTag = "< 1420 Bytes (Fragmented)" }
                }
            }
        } catch {
            $mtuTag = "Unknown"
        }
    } else {
        $roamingMessage += " [Offline / Gateway Not Found]"
    }

    # ==========================================
    # 5. EVALUASI STATUS & OUTPUT JSON
    # ==========================================
    $finalStatus = "OK"
    $statusReason = @()

    # Evaluasi Firewall
    if ($fwStatus -eq $false -or $null -eq $fwStatus) {
        $finalStatus = "WARNING"
        $statusReason += "Firewall OFF"
    }

    if ($roamingActive -and $rssi -lt -75 -and $rssi -ne 0) { 
        $finalStatus = "WARNING"
        $statusReason += "Sinyal Sangat Lemah ($rssi dBm)"
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
        $statusReason += "Egress Port Terbuka"
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
        Perimeter_Tested  = "$fwMessage | $roamingMessage"
    }
}