function controlAuditEndpoint{
    $InformationPreference = 'SilentlyContinue'

    $auditResults = [ordered]@{
        Timestamp          = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        HostName           = $env:COMPUTERNAME
        ProcessorStress    = routeProcessorStressTesting -ReturnData 6>$null
        SystemUpdate       = routeCheckingUpdateSystem -ReturnData 6>$null
        StoragePerformance = routeStoragePerformanceTesting -ReturnData 6>$null
        NetworkPerimeter   = routeNetworkPerimeterTesting -ReturnData 6>$null
        NetworkCoverage    = routeNetworkCoverageTesting -ReturnData 6>$null
        RemoteSession      = routeCheckingRemoteSession -ReturnData 6>$null
    }

    $data = ($auditResults | ConvertTo-Json -Depth 5)

    $summaryData = @()

    # Processor
    $p = $auditResults.ProcessorStress
    $summaryData += [PSCustomObject]@{
        Modul     = "Processor Stress"
        Status    = "PASS"
        Ringkasan = "{0} Pts ({1}s) - {2}" -f $p.PerformanceScore, $p.TimeCompletedSeconds, $p.PCClass
    }

    # Update
    $u = $auditResults.SystemUpdate
    $summaryData += [PSCustomObject]@{
        Modul     = "System Update"
        Status    = if ($u.IsUpToDate) { "PASS" } else { "WARNING" }
        Ringkasan = if ($u.IsUpToDate) { "Sistem Up to Date" } else { "$($u.PendingUpdatesCount) Update Driver Tertunda" }
    }

    # Storage
    $s = $auditResults.StoragePerformance
    $summaryData += [PSCustomObject]@{
        Modul     = "Storage Performance"
        Status    = $s.Status
        Ringkasan = "{0} (Read {1} MB/s)" -f $s.Storage_Tested, $s.Seq_Read_MBps
    }

    # Perimeter
    $np = $auditResults.NetworkPerimeter
    $fwStr = if ($np.Firewall_Active) { "Firewall Aktif" } else { "Firewall Off" }
    
    # [PERBAIKAN]: Lakukan split di luar string pembentuk untuk mencegah parser error
    $dnsTrimmed = if ($np.DNS_Tampering) { $np.DNS_Tampering.Split('(')[0].Trim() } else { "N/A" }
    
    $summaryData += [PSCustomObject]@{
        Modul     = "Network Perimeter"
        Status    = $np.Status
        Ringkasan = "$fwStr | $dnsTrimmed" 
    }

    # Coverage
    $nc = $auditResults.NetworkCoverage
    $summaryData += [PSCustomObject]@{
        Modul     = "Network Coverage"
        Status    = $nc.Status
        Ringkasan = "{0} {1} (Latency {2})" -f $nc.InterfaceType, $nc.SignalOrSpeed, $nc.LatencyStr
    }

    # Remote Session
    $rs = $auditResults.RemoteSession
    $summaryData += [PSCustomObject]@{
        Modul     = "Remote Session"
        Status    = $rs.Status
        Ringkasan = "{0} Sesi Lokal ({1} RDP) | EPEAT: {2}" -f $rs.TotalSessions, $rs.RemoteSessionCount, $rs.EpeatStatus
    }

    # =========================================================================
    # 3. KALKULASI LEBAR DINAMIS BINGKAI TABEL (ASCII DRAWING)
    # =========================================================================
    
    # Cari string terpanjang di masing-masing kolom (dengan batas minimal)
    $lenModul = ($summaryData.Modul | Measure-Object -Property Length -Maximum).Maximum
    if ($lenModul -lt 11) { $lenModul = 11 } # Minimal selebar judul "MODUL AUDIT"

    $lenStatus = ($summaryData.Status | Measure-Object -Property Length -Maximum).Maximum
    if ($lenStatus -lt 6) { $lenStatus = 6 } # Minimal selebar judul "STATUS"

    $lenRingkasan = ($summaryData.Ringkasan | Measure-Object -Property Length -Maximum).Maximum
    if ($lenRingkasan -lt 16) { $lenRingkasan = 16 } # Minimal selebar judul "RINGKASAN TEMUAN"

    # Total lebar area dalam tabel
    $totalInnerWidth = $lenModul + $lenStatus + $lenRingkasan + 8 

    # Pola garis pembatas
    $borderTopBottom = "+{0}+" -f ("-" * $totalInnerWidth)
    $borderMid       = "+-{0}-+-{1}-+-{2}-+" -f ("-" * $lenModul), ("-" * $lenStatus), ("-" * $lenRingkasan)

    # =========================================================================
    # 4. CETAK TABEL KE TERMINAL (MENGGUNAKAN WRITE-HOST / STREAM 6)
    # =========================================================================
    
    Write-Host "`n$borderTopBottom" -ForegroundColor Cyan
    
    # Header Utama (Tengah)
    $title = "RASAMALA v1.0 - ENDPOINT SUMMARY"
    $padLeft = [math]::Floor(($totalInnerWidth - $title.Length) / 2)
    $padRight = $totalInnerWidth - $title.Length - $padLeft
    Write-Host ("|{0}{1}{2}|" -f (" " * $padLeft), $title, (" " * $padRight)) -ForegroundColor Yellow

    # Judul Kolom
    Write-Host $borderMid -ForegroundColor Cyan
    Write-Host ("| {0} | {1} | {2} |" -f "MODUL AUDIT".PadRight($lenModul), "STATUS".PadRight($lenStatus), "RINGKASAN TEMUAN".PadRight($lenRingkasan)) -ForegroundColor Yellow
    Write-Host $borderMid -ForegroundColor Cyan

    # Isi Baris Modul
    $warningCount = 0
    foreach ($row in $summaryData) {
        $color = if ($row.Status -eq "PASS" -or $row.Status -eq "OK") { "Green" } elseif ($row.Status -eq "WARNING") { "Yellow" } else { "Red" }
        
        Write-Host ("| {0} | " -f $row.Modul.PadRight($lenModul)) -NoNewline -ForegroundColor White
        Write-Host ($row.Status.PadRight($lenStatus)) -NoNewline -ForegroundColor $color
        Write-Host (" | {0} |" -f $row.Ringkasan.PadRight($lenRingkasan)) -ForegroundColor White
        
        if ($row.Status -match "WARNING|CRITICAL|FAIL") { $warningCount++ }
    }

    # Baris Status Akhir (Bottom Strip)
    Write-Host $borderMid -ForegroundColor Cyan
    $hostStr = "HOST: $($auditResults.HostName)"
    $statusStr = if ($warningCount -gt 0) { "STATUS AKHIR: WARNING ($warningCount Modul Perlu Perhatian)" } else { "STATUS AKHIR: PASS (Aman)" }
    $bottomText = "$hostStr  |  $statusStr"
    
    Write-Host ("| {0} |" -f $bottomText.PadRight($totalInnerWidth - 2)) -ForegroundColor White
    Write-Host $borderTopBottom -ForegroundColor Cyan
    Write-Host "" # Spasi penutup
}