function controlAqlMonitoring{
    param(
        [int]$InitialInterval = 7,
        [hashtable]$SharedState = $null
    )

    $aqlMatrix = @{
        7  = @{
            'C' = @{ Next = 7;  Mode = 'Emergency' }
            'H' = @{ Next = 14; Mode = 'Reduced' }
            'M' = @{ Next = 14; Mode = 'Reduced' }
            'L' = @{ Next = 14; Mode = 'Reduced' }
        }
        14 = @{
            'C' = @{ Next = 7;  Mode = 'Tightened' }
            'H' = @{ Next = 14; Mode = 'Warning' }
            'M' = @{ Next = 21; Mode = 'Reduced' }
            'L' = @{ Next = 21; Mode = 'Reduced' }
        }
        21 = @{
            'C' = @{ Next = 7;  Mode = 'Tightened' }
            'H' = @{ Next = 14; Mode = 'Tightened' }
            'M' = @{ Next = 21; Mode = 'Normal' }
            'L' = @{ Next = 35; Mode = 'Reduced' }
        }
        35 = @{
            'C' = @{ Next = 7;  Mode = 'Tightened' }
            'H' = @{ Next = 14; Mode = 'Tightened' }
            'M' = @{ Next = 21; Mode = 'Tightened' }
            'L' = @{ Next = 35; Mode = 'Eco' }
        }
    }

    $currentInterval = $InitialInterval
    $currentMode     = "Initial"
    $loopCount       = 1
    
    $lastInput       = $null
    $lastInterval    = $null
    $lastMode        = $null

    while ($true) {
        Clear-Host
        helperBanner

        $metricRowPos = 0
        if ($null -ne $SharedState) {
            Write-Host "`n=== LIVE ENDPOINT METRICS ===" @Net
            Write-Host ("{0,-21} {1,-12} {2,-15} {3,-13} {4,-15}" -f "Timestamp", "CPU_Usage", "RAM_Usage", "Active_Conn", "Net_Status") @Cha
            Write-Host ("{0,-21} {1,-12} {2,-15} {3,-13} {4,-15}" -f "---------", "---------", "---------", "-----------", "----------") @Cha
            
            $metricRowPos = [Console]::CursorTop
            Write-Host "`n" 
        }

        Write-Host "==========================================================" @Dim
        Write-Host "              AQL STATISTICAL DEEP MONITORING              " @Net
        Write-Host "==========================================================" @Dim
        
        $unitLabel = "Minute"

        if ($loopCount -gt 1) {
            Write-Host " [CYCLE HISTORY #$($loopCount - 1)]" @Dim
            Write-Host "  * Analyst Input  : $lastInput"
            Write-Host "  * Transition     : $lastInterval $unitLabel ($lastMode) ---> $currentInterval $unitLabel ($currentMode)" -ForegroundColor Gray
            Write-Host "----------------------------------------------------------" @Dim
        }

        Write-Host " [ACTIVE MONITORING STATUS - CYCLE #$loopCount]" @Net
        Write-Host "  * Current Interval : $currentInterval $unitLabel" -ForegroundColor White
        Write-Host "  * Operational Mode : $currentMode" -ForegroundColor White
        Write-Host "----------------------------------------------------------" @Dim

        $waitTimeInSeconds = $currentInterval * 60
        
        for ($i = $waitTimeInSeconds; $i -gt 0; $i--) {
            # === PERBAIKAN DI BLOK INI ===
            if ($null -ne $SharedState -and $metricRowPos -gt 0 -and $SharedState.ContainsKey('Timestamp')) {
                $currentTop = [Console]::CursorTop 
                $currentLeft = [Console]::CursorLeft
                
                # Lompat ke atas
                [Console]::SetCursorPosition(0, $metricRowPos) 
                
                $rowData = "{0,-21} {1,-12} {2,-15} {3,-13} {4,-15}" -f $SharedState.Timestamp, "$($SharedState.CPU) %", "$($SharedState.RAM) MB", $SharedState.Active_Conn, $SharedState.Net_Status
                
                # Gunakan [Console]::Write agar tidak ada karakter NewLine yang merusak buffer
                [Console]::Write($rowData.PadRight(85))
                
                # Kembali ke posisi semula
                [Console]::SetCursorPosition($currentLeft, $currentTop) 
            }
            # =============================

            Write-Progress -Activity "Monitoring AQL Running" -Status "Next Alarm in $i seconds..." -PercentComplete (($waitTimeInSeconds - $i) / $waitTimeInSeconds * 100)
            Start-Sleep -Seconds 1
        }
        Write-Progress -Activity "AQL Monitoring Conducted" -Completed

        Write-Host "`n [!] ALARM RINGING! PLEASE ENTER THE THREAT STATUS [!]" @Pen -BackgroundColor Yellow
        
        $alarmThread = [powershell]::Create().AddScript({
            while ($true) {
                [console]::Beep(1000, 600)
                Start-Sleep -Milliseconds 200
            }
        })
        $null = $alarmThread.BeginInvoke()

        try {
            $validInput = $false
            $severity   = ""

            while (-not $validInput) {
                Write-Host "`n Enter Current Threat Status:" @Cha
                Write-Host "   [C] Critical" @Pen
                Write-Host "   [H] High"     @Inc
                Write-Host "   [M] Medium"   @Cha
                Write-Host "   [L] Low"      @App
                Write-Host "   [Q] Quit Session" -ForegroundColor Red
                
                $inputRaw = Read-Host "`n Pilihan Anda (C/H/M/L/Q)"
                
                if (-not [string]::IsNullOrWhiteSpace($inputRaw)) {
                    $severity = $inputRaw.Trim().Substring(0, 1).ToUpper()
                }

                if ($severity -eq 'Q') {
                    Write-Host "`n[!] Menutup Sesi AQL Monitoring..." -ForegroundColor Yellow
                    return 
                }

                if ($severity -in @('C', 'H', 'M', 'L')) {
                    $validInput = $true
                } else {
                    Write-Host " Pilihan tidak valid! Harap masukkan C, H, M, L atau Q untuk keluar." @Pen
                }
            }
        }
        finally {
            if ($alarmThread) {
                $alarmThread.Stop()
                $alarmThread.Dispose()
            }
        }

        $lastInput    = $severity
        $lastInterval = $currentInterval
        $lastMode     = $currentMode

        $transition       = $aqlMatrix[$currentInterval][$severity]
        $nextInterval     = $transition.Next
        $nextMode         = $transition.Mode

        $currentInterval = $nextInterval
        $currentMode     = $nextMode
        $loopCount       ++
    }
}