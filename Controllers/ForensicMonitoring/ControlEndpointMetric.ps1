function controlEndpointMetric{
    param(
        [switch]$SingleRun,
        [switch]$RawDataOnly,
        [hashtable]$SharedState = $null
    )

    # Deteksi OS yang kompatibel untuk Windows PowerShell 5.1 maupun PowerShell 7+
    $osPlatform = if ($null -ne $IsWindows -and $IsWindows) {
        'Windows'
    }
    elseif ($null -ne $IsLinux -and $IsLinux) {
        'Linux'
    }
    elseif ($null -ne $IsMacOS -and $IsMacOS) {
        'macOS'
    }
    elseif ($env:OS -eq 'Windows_NT') {
        'Windows'
    }
    else {
        'Unknown'
    }

    if (-not $RawDataOnly -and $null -eq $SharedState) {
        Clear-Host
        if (Get-Command -Name 'showBanner' -ErrorAction SilentlyContinue) {
            showBanner
        }

        Write-Host "`n=== LIVE ENDPOINT METRICS ===" @Net
        Write-Host ("{0,-21} {1,-12} {2,-15} {3,-13} {4,-15}" -f "Timestamp", "CPU_Usage", "RAM_Usage", "Active_Conn", "Net_Status") @Cha
        Write-Host ("{0,-21} {1,-12} {2,-15} {3,-13} {4,-15}" -f "---------", "---------", "---------", "-----------", "----------") @Cha

        try {
            $dataRowPosition = [Console]::CursorTop
            [Console]::CursorVisible = $false
        }
        catch {
            $dataRowPosition = 0
        }
    }

    $pingT = New-Object System.Net.NetworkInformation.Ping

    # State pembacaan delta CPU untuk Linux (/proc/stat)
    $prevLinuxCpuTotal = $null
    $prevLinuxCpuIdle  = $null

    # Cache pemetaan port hardware macOS (en0 -> Wi-Fi/LAN) agar tidak dipanggil berulang di dalam loop
    $macHardwarePorts = @{}
    if ($osPlatform -eq 'macOS' -and (Get-Command -Name 'networksetup' -ErrorAction SilentlyContinue)) {
        $hwOutput = & networksetup -listallhardwareports 2>$null
        $currentPort = ''
        foreach ($line in $hwOutput) {
            if ($line -match '^Hardware Port:\s*(.+)$') {
                $currentPort = $Matches[1].Trim()
            }
            elseif ($line -match '^Device:\s*(\S+)$' -and $currentPort) {
                $macHardwarePorts[$Matches[1].Trim()] = $currentPort
            }
        }
    }

    # Helper internal untuk membaca counter CPU Linux dari /proc/stat
    $ReadLinuxCpuCounters = {
        $firstLine = Get-Content -Path '/proc/stat' -TotalCount 1 -ErrorAction SilentlyContinue
        if ($firstLine -match '^cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)(?:\s+(\d+))?') {
            $user    = [double]$Matches[1]
            $nice    = [double]$Matches[2]
            $system  = [double]$Matches[3]
            $idle    = [double]$Matches[4]
            $iowait  = [double]$Matches[5]
            $irq     = [double]$Matches[6]
            $softirq = [double]$Matches[7]
            $steal   = if ($Matches[8]) { [double]$Matches[8] } else { 0 }

            $idleAll = $idle + $iowait
            $total   = $idleAll + $user + $nice + $system + $irq + $softirq + $steal
            return @{ Total = $total; Idle = $idleAll }
        }
        return $null
    }

    try {
        while ($true) {
            $cpu = 0
            $ram = 0
            $net = 0
            $netStatus = "Offline"
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

            switch ($osPlatform) {
                'Windows' {
                    # 1. CPU Windows
                    $cpuObj = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average
                    $cpu = if ($null -ne $cpuObj.Average) { [math]::Round($cpuObj.Average, 0) } else { 0 }

                    # 2. RAM Windows
                    $os = Get-CimInstance Win32_OperatingSystem
                    $ram = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1024), 2)

                    # 3. Koneksi Aktif Windows
                    $net = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue).Count

                    # 4. Status Jaringan Windows
                    $activeNet = Get-NetIPConfiguration | Where-Object { $null -ne $_.IPv4DefaultGateway } | Select-Object -First 1
                    if ($activeNet) {
                        $adapterName = $activeNet.InterfaceAlias
                        $netType = if ($adapterName -match "Wi-Fi|Wireless") { "WiFi" } else { "LAN" }
                        $netStatus = "$netType (Checking)"
                    }
                }

                'Linux' {
                    # 1. CPU Linux via /proc/stat (delta sampling tanpa spawn proses eksternal)
                    if ($null -eq $prevLinuxCpuTotal) {
                        $c1 = & $ReadLinuxCpuCounters
                        Start-Sleep -Milliseconds 200
                        $c2 = & $ReadLinuxCpuCounters
                        if ($c1 -and $c2 -and ($c2.Total -gt $c1.Total)) {
                            $totalDelta = $c2.Total - $c1.Total
                            $idleDelta  = $c2.Idle - $c1.Idle
                            $cpu = [math]::Round((($totalDelta - $idleDelta) / $totalDelta) * 100, 0)
                            $prevLinuxCpuTotal = $c2.Total
                            $prevLinuxCpuIdle  = $c2.Idle
                        }
                    }
                    else {
                        $cNow = & $ReadLinuxCpuCounters
                        if ($cNow -and ($cNow.Total -gt $prevLinuxCpuTotal)) {
                            $totalDelta = $cNow.Total - $prevLinuxCpuTotal
                            $idleDelta  = $cNow.Idle - $prevLinuxCpuIdle
                            $cpu = [math]::Round((($totalDelta - $idleDelta) / $totalDelta) * 100, 0)
                            $prevLinuxCpuTotal = $cNow.Total
                            $prevLinuxCpuIdle  = $cNow.Idle
                        }
                    }

                    # 2. RAM Linux via /proc/meminfo
                    $memInfo = Get-Content -Path '/proc/meminfo' -ErrorAction SilentlyContinue
                    $memTotalKb = 0
                    $memAvailKb = 0
                    foreach ($line in $memInfo) {
                        if ($line -match '^MemTotal:\s+(\d+)\s+kB') { $memTotalKb = [double]$Matches[1] }
                        elseif ($line -match '^MemAvailable:\s+(\d+)\s+kB') { $memAvailKb = [double]$Matches[1] }
                    }
                    if ($memTotalKb -gt 0) {
                        $ram = [math]::Round((($memTotalKb - $memAvailKb) / 1024), 2)
                    }

                    # 3. Koneksi Aktif Linux via /proc/net/tcp & /proc/net/tcp6 (State 01 = ESTABLISHED)
                    $estCount = 0
                    foreach ($tcpFile in @('/proc/net/tcp', '/proc/net/tcp6')) {
                        if (Test-Path -Path $tcpFile) {
                            $lines = Get-Content -Path $tcpFile -ErrorAction SilentlyContinue
                            foreach ($l in $lines) {
                                if ($l -match '^\s*\d+:\s+[0-9A-Fa-f]+:[0-9A-Fa-f]+\s+[0-9A-Fa-f]+:[0-9A-Fa-f]+\s+01\b') {
                                    $estCount++
                                }
                            }
                        }
                    }
                    $net = $estCount

                    # 4. Status Jaringan Linux via /proc/net/route & sysfs
                    $activeIface = $null
                    if (Test-Path -Path '/proc/net/route') {
                        $routes = Get-Content -Path '/proc/net/route' -ErrorAction SilentlyContinue | Select-Object -Skip 1
                        foreach ($r in $routes) {
                            $cols = $r -split '\s+'
                            if ($cols.Count -ge 4 -and $cols[1] -eq '00000000' -and (([convert]::ToInt32($cols[3], 16) -band 2) -ne 0)) {
                                $activeIface = $cols[0]
                                break
                            }
                        }
                    }
                    if ($activeIface) {
                        $isWifi = (Test-Path -Path "/sys/class/net/$activeIface/wireless") -or ($activeIface -match '^(wl|wlan|wifi)')
                        $netType = if ($isWifi) { "WiFi" } else { "LAN" }
                        $netStatus = "$netType (Checking)"
                    }
                }

                'macOS' {
                    # 1. CPU macOS via top
                    $topOut = & top -l 1 -n 0 -s 0 2>$null
                    foreach ($line in $topOut) {
                        if ($line -match 'CPU usage:\s+([\d.]+)%\s+user,\s+([\d.]+)%\s+sys') {
                            $cpu = [math]::Round(([double]$Matches[1] + [double]$Matches[2]), 0)
                            break
                        }
                    }

                    # 2. RAM macOS via sysctl & vm_stat
                    $pageSize = [double](& sysctl -n hw.pagesize 2>$null)
                    $vmOut = & vm_stat 2>$null
                    $activePages = 0; $wiredPages = 0; $compressedPages = 0
                    foreach ($line in $vmOut) {
                        if ($line -match '^Pages active:\s+(\d+)\.') { $activePages = [double]$Matches[1] }
                        elseif ($line -match '^Pages wired down:\s+(\d+)\.') { $wiredPages = [double]$Matches[1] }
                        elseif ($line -match '^Pages occupied by compressor:\s+(\d+)\.') { $compressedPages = [double]$Matches[1] }
                    }
                    if ($pageSize -gt 0) {
                        $usedBytes = ($activePages + $wiredPages + $compressedPages) * $pageSize
                        $ram = [math]::Round(($usedBytes / 1MB), 2)
                    }

                    # 3. Koneksi Aktif macOS via netstat
                    $net = @(& netstat -an -p tcp 2>$null | Where-Object { $_ -match '\bESTABLISHED\b' }).Count

                    # 4. Status Jaringan macOS via route & networksetup
                    $routeOut = & route -n get default 2>$null
                    $activeIface = $null
                    foreach ($line in $routeOut) {
                        if ($line -match 'interface:\s+(\S+)') {
                            $activeIface = $Matches[1].Trim()
                            break
                        }
                    }
                    if ($activeIface) {
                        $portLabel = $macHardwarePorts[$activeIface]
                        $netType = if ($portLabel -match 'Wi-Fi|AirPort|Wireless') { "WiFi" } else { "LAN" }
                        $netStatus = "$netType (Checking)"
                    }
                }
            }

            # Pengukuran Latensi Ping Lintas Platform (jika interface aktif terdeteksi)
            if ($netStatus -ne "Offline") {
                try {
                    $reply = $pingT.Send("8.8.8.8", 500)
                    if ($reply.Status -eq 'Success') {
                        $netStatus = "$netType ($($reply.RoundtripTime)ms)"
                    }
                    else {
                        $netStatus = "$netType (RTO)"
                    }
                }
                catch {
                    # Fallback ke binary ping OS (penting di Linux/macOS jika .NET Ping diblokir izin non-root)
                    if ($osPlatform -in @('Linux', 'macOS')) {
                        $pingFlag = if ($osPlatform -eq 'macOS') { '-t' } else { '-W' }
                        $pingOut = & ping -c 1 $pingFlag 1 8.8.8.8 2>$null
                        if ($LASTEXITCODE -eq 0 -and ($pingOut -join ' ') -match 'time=([\d.]+)\s*ms') {
                            $ms = [math]::Round([double]$Matches[1], 0)
                            $netStatus = "$netType (${ms}ms)"
                        }
                        else {
                            $netStatus = "$netType (RTO)"
                        }
                    }
                    else {
                        $netStatus = "$netType (Error)"
                    }
                }
            }

            if ($null -ne $SharedState) {
                $SharedState.Timestamp      = $timestamp
                $SharedState.CPU            = $cpu
                $SharedState.RAM            = $ram
                $SharedState.Active_Conn    = $net
                $SharedState.Net_Status     = $netStatus
                $SharedState.TelemetryReady = $true
            }
            elseif ($RawDataOnly) {
                return [pscustomobject]@{
                    Timestamp   = $timestamp
                    CPU         = $cpu
                    RAM         = $ram
                    Active_Conn = $net
                    Net_Status  = $netStatus
                }
            }
            else {
                $cpuStr    = "$cpu %"
                $ramStr    = "$ram MB"
                $netStr    = "$net"
                $statusStr = $netStatus

                try {
                    [Console]::SetCursorPosition(0, $dataRowPosition)
                }
                catch {}
                $rowData = "{0,-21} {1,-12} {2,-15} {3,-13} {4,-15}" -f $timestamp, $cpuStr, $ramStr, $netStr, $statusStr
                Write-Host $rowData.PadRight(85)

                try {
                    [Console]::SetCursorPosition(0, $dataRowPosition + 2)
                }
                catch {}
                Write-Host "Memperbarui data setiap 2 detik... (Tekan Ctrl+C untuk keluar)" @Dim
            }

            if ($SingleRun) { break }
            if ($null -ne $SharedState -and $SharedState.KeepRunning -eq $false) { break }

            Start-Sleep -Seconds 2
        }
    }
    finally {
        if (-not $RawDataOnly -and $null -eq $SharedState) {
            try { [Console]::CursorVisible = $true } catch {}
            Write-Host "`n`nLive Monitoring dihentikan." @Pen
        }
        if ($pingT) { $pingT.Dispose() }
    }
}