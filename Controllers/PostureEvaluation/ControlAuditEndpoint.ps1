function controlAuditEndpoint{
    $InformationPreference = 'SilentlyContinue'

    $auditResults = [ordered]@{
        Timestamp          = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        HostName           = [Environment]::MachineName
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
        Ringkasan = "{0} (Read {1} MB/s)" -f $s.StorageTested, $s.SeqReadMBps
    }

    $np = $auditResults.NetworkPerimeter
    $fwStr = if ($np.FirewallActive) { "Active Firewall" } else { "Firewall Off" }
    
    $dnsTrimmed = if ($np.DNSTampering) { $np.DNSTampering.Split('(')[0].Trim() } else { "N/A" }
    
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

    $r3  = "■ R3:User"
    $r0  = "□ R0:Kernel"
    $rm1 = "□ R-1:Hypervisor"
    $rm2 = "□ R-2:Firmware"
    $rm3 = "□ R-3:Chipset"

    if ($IsWindows) {
        $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if ($isAdmin) {
            $r0 = "■ R0:Kernel"
            
            $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
            if ($cs -and $cs.HypervisorPresent) { $rm1 = "■ R-1:Hypervisor" }

            $uefi = Test-Path "HKLM:\System\CurrentControlSet\Control\SecureBoot\State"
            if ($uefi) { $rm2 = "■ R-2:Firmware" }

            $chipset = Get-CimInstance Win32_PnPEntity -Filter "Name LIKE '%Management Engine%' OR Name LIKE '%Platform Security Processor%'" -ErrorAction SilentlyContinue
            if ($chipset) { $rm3 = "■ R-3:Chipset" }
        }
    } 
    elseif ($IsLinux) {
        # Pengecekan akses Root pada Linux
        $isRoot = ([Environment]::UserName -eq 'root') -or ((id -u 2>$null) -eq '0')

        if ($isRoot) {
            $r0 = "■ R0:Kernel"

            # Deteksi Hypervisor di Linux (/sys atau /proc/cpuinfo)
            if ((Test-Path "/sys/hypervisor/type") -or (Select-String -Path "/proc/cpuinfo" -Pattern "hypervisor" -Quiet -ErrorAction SilentlyContinue)) { 
                $rm1 = "■ R-1:Hypervisor" 
            }

            # Deteksi UEFI Firmware di Linux (/sys/firmware/efi)
            if (Test-Path "/sys/firmware/efi") { 
                $rm2 = "■ R-2:Firmware" 
            }

            # Deteksi Chipset Engine (Intel ME / AMD PSP) via device node atau lspci
            if ((Test-Path "/dev/mei0") -or (lspci 2>$null | Select-String -Pattern "Management Engine|PSP")) { 
                $rm3 = "■ R-3:Chipset" 
            }
        }
    }

    Write-Host "SCOPE│" -NoNewline -ForegroundColor DarkGray
    Write-Host "$r3 " -NoNewline -ForegroundColor Cyan
    Write-Host "│" -NoNewline -ForegroundColor DarkGray
    
    $rings = @($r0, $rm1, $rm2, $rm3)
    foreach ($ring in $rings) {
        if ($ring -match "■") { 
            Write-Host "$ring " -NoNewline -ForegroundColor Green
        } else { 
            Write-Host "$ring " -NoNewline -ForegroundColor DarkGray
        }
        
        if ($ring -ne $rings[-1]) { 
            Write-Host "│" -NoNewline -ForegroundColor DarkGray 
        }
    }
    Write-Host "`n"
}
