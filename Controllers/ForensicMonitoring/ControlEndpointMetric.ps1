. $PSScriptRoot\..\..\Config\Windows.ps1

function controlEndpointMetric{
    # 1. Bersihkan layar dan tampilkan banner SEKALI SAJA di awal
    Clear-Host
    showBanner 
    
    Write-Host "`n=== LIVE ENDPOINT METRICS ===" @Net
    # Menambahkan kolom Net_Status (Jaringan)
    Write-Host "Timestamp            CPU_Usage   RAM_Usage   Active_Conn Net_Status" @Cha
    Write-Host "---------            ---------   ---------   ----------- ----------" @Cha

    # 2. Simpan posisi baris kursor saat ini (tempat data akan ditulis)
    $dataRowPosition = [Console]::CursorTop
    [Console]::CursorVisible = $false
    
    # Siapkan alat Ping .NET (Sangat cepat, tidak bikin loop nge-lag)
    $pingT = New-Object System.Net.NetworkInformation.Ping

    try {
        while ($true) {
            # --- MULAI PENGAMBILAN DATA ---
            $cpuObj = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average
            $cpu = if ($null -ne $cpuObj.Average) { $cpuObj.Average } else { 0 }
            
            $os = Get-CimInstance Win32_OperatingSystem
            $ram = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1024), 2)
            
            $net = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue).Count
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

            # --- CEK KELANCARAN JARINGAN (LAN / WI-FI) ---
            $netStatus = "Offline"
            # Cari adapter yang punya akses gateway (internet)
            $activeNet = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -ne $null } | Select-Object -First 1
            
            if ($activeNet) {
                # Tentukan namanya (Wi-Fi atau LAN)
                $adapterName = $activeNet.InterfaceAlias
                $netType = if ($adapterName -match "Wi-Fi|Wireless") { "WiFi" } else { "LAN" }
                
                try {
                    # Tembak Ping cepat ke 8.8.8.8 dengan batas waktu 500ms (setengah detik)
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

            # --- FORMAT DAN TAMPILKAN ---
            $cpuStr    = "$cpu %".PadRight(11)
            $ramStr    = "$ram MB".PadRight(11)
            $netStr    = "$net".PadRight(11)
            $statusStr = $netStatus.PadRight(15) # Spasi ekstra untuk kolom baru

            # Pindahkan kursor KEMBALI ke posisi baris data lalu timpa
            [Console]::SetCursorPosition(0, $dataRowPosition)
            Write-Host "$timestamp  $cpuStr $ramStr $netStr $statusStr           "

            # Tulis pesan informasi di bawahnya
            [Console]::SetCursorPosition(0, $dataRowPosition + 2)
            Write-Host "Memperbarui data setiap 2 detik... (Tekan Ctrl+C untuk keluar)" @Dim
            
            # Jeda 2 detik
            Start-Sleep -Seconds 2
        }
    }
    finally {
        [Console]::CursorVisible = $true
        Write-Host "`n`nLive Monitoring dihentikan." @Pen
        if ($pingT) { $pingT.Dispose() } # Bersihkan memori ping
    }
}