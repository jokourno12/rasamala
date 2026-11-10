. $PSScriptRoot\..\..\Config\Windows.ps1

function controlAqlMonitoring{
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
            Write-Progress -Activity "Monitoring AQL Running" -Status "Next Alarm in $i seconds..." -PercentComplete (($waitTimeInSeconds - $i) / $waitTimeInSeconds * 100)
            Start-Sleep -Seconds 1
        }
        Write-Progress -Activity "AQL Monitoring Conducted" -Completed

        Write-Host "`n [!] ALARM RINGING! PLEASE ENTER THE THREAT STATUS [!]" @Pen -BackgroundColor Yellow
        
        # ----------------------------------------------------------------------
        # ALARM BUNYI CONTINUOUS (BACKGROUND THREAD)
        # ----------------------------------------------------------------------
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
                
                $inputRaw = Read-Host "`n Pilihan Anda (C/H/M/L atau Critical/High/Medium/Low)"
                
                if (-not [string]::IsNullOrWhiteSpace($inputRaw)) {
                    $severity = $inputRaw.Trim().Substring(0, 1).ToUpper()
                }

                if ($severity -in @('C', 'H', 'M', 'L')) {
                    $validInput = $true
                } else {
                    Write-Host " Pilihan tidak valid! Harap masukkan C, H, M, L atau nama statusnya." @Pen
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