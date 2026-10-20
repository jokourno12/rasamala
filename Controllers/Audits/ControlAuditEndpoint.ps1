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

    $p = $auditResults.ProcessorStress
    $summaryData += [PSCustomObject]@{
        Modul     = "Processor Stress"
        Status    = "PASS"
        Ringkasan = "{0} Pts ({1}s) - {2}" -f $p.PerformanceScore, $p.TimeCompletedSeconds, $p.PCClass
    }

    $u = $auditResults.SystemUpdate
    $summaryData += [PSCustomObject]@{
        Modul     = "System Update"
        Status    = if ($u.IsUpToDate) { "PASS" } else { "WARNING" }
        Ringkasan = if ($u.IsUpToDate) { "Sistem Up to Date" } else { "$($u.PendingUpdatesCount) Pending Driver Updates" }
    }

    $s = $auditResults.StoragePerformance
    $summaryData += [PSCustomObject]@{
        Modul     = "Storage Performance"
        Status    = $s.Status
        Ringkasan = "{0} (Read {1} MB/s)" -f $s.Storage_Tested, $s.Seq_Read_MBps
    }

    $np = $auditResults.NetworkPerimeter
    $fwStr = if ($np.Firewall_Active) { "Active Firewall" } else { "Firewall Off" }
    
    $dnsTrimmed = if ($np.DNS_Tampering) { $np.DNS_Tampering.Split('(')[0].Trim() } else { "N/A" }
    
    $summaryData += [PSCustomObject]@{
        Modul     = "Network Perimeter"
        Status    = $np.Status
        Ringkasan = "$fwStr | $dnsTrimmed" 
    }

    $nc = $auditResults.NetworkCoverage
    $summaryData += [PSCustomObject]@{
        Modul     = "Network Coverage"
        Status    = $nc.Status
        Ringkasan = "{0} {1} (Latency {2})" -f $nc.InterfaceType, $nc.SignalOrSpeed, $nc.LatencyStr
    }

    $rs = $auditResults.RemoteSession
    $summaryData += [PSCustomObject]@{
        Modul     = "Remote Session"
        Status    = $rs.Status
        Ringkasan = "{0} Local Sessions ({1} RDP) | EPEAT: {2}" -f $rs.TotalSessions, $rs.RemoteSessionCount, $rs.EpeatStatus
    }

    $lenModul = ($summaryData.Modul | Measure-Object -Property Length -Maximum).Maximum
    if ($lenModul -lt 11) { $lenModul = 11 } 

    $lenStatus = ($summaryData.Status | Measure-Object -Property Length -Maximum).Maximum
    if ($lenStatus -lt 6) { $lenStatus = 6 } 

    $lenRingkasan = ($summaryData.Ringkasan | Measure-Object -Property Length -Maximum).Maximum
    if ($lenRingkasan -lt 16) { $lenRingkasan = 16 } 

    $totalInnerWidth = $lenModul + $lenStatus + $lenRingkasan + 8 

    $borderTopBottom = "+{0}+" -f ("-" * $totalInnerWidth)
    $borderMid       = "+-{0}-+-{1}-+-{2}-+" -f ("-" * $lenModul), ("-" * $lenStatus), ("-" * $lenRingkasan)
  
    Write-Host "`n$borderTopBottom" -ForegroundColor Cyan
    
    $title = "RASAMALA v1.0 - ENDPOINT SUMMARY"
    $padLeft = [math]::Floor(($totalInnerWidth - $title.Length) / 2)
    $padRight = $totalInnerWidth - $title.Length - $padLeft
    Write-Host ("|{0}{1}{2}|" -f (" " * $padLeft), $title, (" " * $padRight)) -ForegroundColor Yellow

    Write-Host $borderMid -ForegroundColor Cyan
    Write-Host ("| {0} | {1} | {2} |" -f "AUDIT MODULE".PadRight($lenModul), "STATUS".PadRight($lenStatus), "SUMMARY FINDINGS".PadRight($lenRingkasan)) -ForegroundColor Yellow
    Write-Host $borderMid -ForegroundColor Cyan

    $warningCount = 0
    foreach ($row in $summaryData) {
        $color = if ($row.Status -eq "PASS" -or $row.Status -eq "OK") { "Green" } elseif ($row.Status -eq "WARNING") { "Yellow" } else { "Red" }
        
        Write-Host ("| {0} | " -f $row.Modul.PadRight($lenModul)) -NoNewline -ForegroundColor White
        Write-Host ($row.Status.PadRight($lenStatus)) -NoNewline -ForegroundColor $color
        Write-Host (" | {0} |" -f $row.Ringkasan.PadRight($lenRingkasan)) -ForegroundColor White
        
        if ($row.Status -match "WARNING|CRITICAL|FAIL") { $warningCount++ }
    }

    Write-Host $borderMid -ForegroundColor Cyan
    $hostStr = "HOST: $($auditResults.HostName)"
    $statusStr = if ($warningCount -gt 0) { "FINAL STATUS: WARNING ($warningCount Module Needs Attention)" } else { "FINAL STATUS: PASS (Well Architected)" }
    $bottomText = "$hostStr  |  $statusStr"
    
    Write-Host ("| {0} |" -f $bottomText.PadRight($totalInnerWidth - 2)) -ForegroundColor White
    Write-Host $borderTopBottom -ForegroundColor Cyan
    Write-Host ""
}