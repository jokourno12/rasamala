function controlEndpointMetric{
    param(
        [switch]$SingleRun,
        [switch]$RawDataOnly,
        [hashtable]$SharedState = $null
    )

    if (-not $RawDataOnly -and $null -eq $SharedState) {
        Clear-Host
        showBanner 
        
        Write-Host "`n=== LIVE ENDPOINT METRICS ===" @Net
        Write-Host ("{0,-21} {1,-12} {2,-15} {3,-13} {4,-15}" -f "Timestamp", "CPU_Usage", "RAM_Usage", "Active_Conn", "Net_Status") @Cha
        Write-Host ("{0,-21} {1,-12} {2,-15} {3,-13} {4,-15}" -f "---------", "---------", "---------", "-----------", "----------") @Cha

        $dataRowPosition = [Console]::CursorTop
        [Console]::CursorVisible = $false
    }
    
    $pingT = New-Object System.Net.NetworkInformation.Ping

    try {
        while ($true) {
            $cpuObj = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average
            $cpu = if ($null -ne $cpuObj.Average) { $cpuObj.Average } else { 0 }
            
            $os = Get-CimInstance Win32_OperatingSystem
            $ram = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1024), 2)
            
            $net = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue).Count
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

            $netStatus = "Offline"
            $activeNet = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null } | Select-Object -First 1
            
            if ($activeNet) {
                $adapterName = $activeNet.InterfaceAlias
                $netType = if ($adapterName -match "Wi-Fi|Wireless") { "WiFi" } else { "LAN" }
                
                try {
                    $reply = $pingT.Send("8.8.8.8", 500)
                    if ($reply.Status -eq 'Success') {
                        $netStatus = "$netType ($($reply.RoundtripTime)ms)"
                    } else {
                        $netStatus = "$netType (RTO)"
                    }
                } catch {
                    $netStatus = "$netType (Error)"
                }
            }

            if ($null -ne $SharedState) {
                $SharedState.Timestamp   = $timestamp
                $SharedState.CPU         = $cpu
                $SharedState.RAM         = $ram
                $SharedState.Active_Conn = $net
                $SharedState.Net_Status  = $netStatus
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

                [Console]::SetCursorPosition(0, $dataRowPosition)
                $rowData = "{0,-21} {1,-12} {2,-15} {3,-13} {4,-15}" -f $timestamp, $cpuStr, $ramStr, $netStr, $statusStr
                Write-Host $rowData.PadRight(85)

                [Console]::SetCursorPosition(0, $dataRowPosition + 2)
                Write-Host "Memperbarui data setiap 2 detik... (Tekan Ctrl+C untuk keluar)" @Dim
            }
            
            if ($SingleRun) { break }
            if ($null -ne $SharedState -and $SharedState.KeepRunning -eq $false) { break }

            Start-Sleep -Seconds 2
        }
    }
    finally {
        if (-not $RawDataOnly -and $null -eq $SharedState) {
            [Console]::CursorVisible = $true
            Write-Host "`n`nLive Monitoring dihentikan." @Pen
        }
        if ($pingT) { $pingT.Dispose() }
    }
}