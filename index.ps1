[CmdletBinding()]
param(
    [switch]$OperatingSystem,
    [switch]$CheckingUpdateSystem,
    [switch]$CheckingDiskEncryption,
    [switch]$CheckingFirewall,
    [switch]$CheckingNetworkPorts,
    [switch]$CheckingRemoteSession,
    [switch]$CheckingOutboundConnection,
    [switch]$EndpointMetric,
    [switch]$AqlMonitoring,
    [switch]$F5Reset,

    [ValidateSet(7, 14, 28, 42)]
    [int]$InitialInterval = 7
)

#Support
. $PSScriptRoot\Helpers\Banner.ps1
. $PSScriptRoot\Routes\Audit.ps1
. $PSScriptRoot\Routes\Operation.ps1
. $PSScriptRoot\Routes\Remediation.ps1

function showBanner {
    helperBanner
}

showBanner
# Audit
if ($OperatingSystem){
    routeOperatingSystem
}

if ($CheckingUpdateSystem){
    routeCheckingUpdateSystem
}

if ($CheckingDiskEncryption){
    routeCheckingDiskEncryption
}

if ($CheckingFirewall){
    routeCheckingFirewall
}

if ($CheckingNetworkPorts){
    routeCheckingNetworkPorts
}

if ($CheckingRemoteSession){
    routeCheckingRemoteSession
}

if ($CheckingOutboundConnection){
    routeCheckingOutboundConnection
}

# Operation
if ($EndpointMetric){
    routeEndpointMetric
}

if ($AqlMonitoring){
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
            'M' = @{ Next = 28; Mode = 'Reduced' }
            'L' = @{ Next = 28; Mode = 'Reduced' }
        }
        28 = @{
            'C' = @{ Next = 7;  Mode = 'Tightened' }
            'H' = @{ Next = 14; Mode = 'Tightened' }
            'M' = @{ Next = 28; Mode = 'Normal' }
            'L' = @{ Next = 42; Mode = 'Reduced' }
        }
        42 = @{
            'C' = @{ Next = 7;  Mode = 'Tightened' }
            'H' = @{ Next = 14; Mode = 'Tightened' }
            'M' = @{ Next = 28; Mode = 'Tightened' }
            'L' = @{ Next = 42; Mode = 'Eco' }
        }
    }

    $currentInterval = $InitialInterval
    $currentMode     = "Initial / Emergency"
    $loopCount       = 1
    
    $lastInput       = $null
    $lastInterval    = $null
    $lastMode        = $null

    while ($true) {
        Clear-Host

        Write-Host "==========================================================" -ForegroundColor Cyan
        Write-Host "          AQL SECOPS DYNAMIC MONITORING SYSTEM          " -ForegroundColor Yellow
        Write-Host "==========================================================" -ForegroundColor Cyan
        
        $unitLabel = "Minute"

        if ($loopCount -gt 1) {
            Write-Host " [HISTORI SIKLUS #$($loopCount - 1)]" -ForegroundColor DarkGray
            Write-Host "  * Input Analis  : $lastInput" -ForegroundColor Yellow
            Write-Host "  * Transisi      : $lastInterval $unitLabel ($lastMode) ---> $currentInterval $unitLabel ($currentMode)" -ForegroundColor Gray
            Write-Host "----------------------------------------------------------" -ForegroundColor Cyan
        }

        Write-Host " [ACTIVE MONITORING STATUS - CYCLE #$loopCount]" -ForegroundColor Green
        Write-Host "  * Current Interval : $currentInterval $unitLabel" -ForegroundColor White
        Write-Host "  * Operational Mode : $currentMode" -ForegroundColor White
        Write-Host "----------------------------------------------------------" -ForegroundColor Cyan

        $waitTimeInSeconds = $currentInterval * 60
        
        for ($i = $waitTimeInSeconds; $i -gt 0; $i--) {
            Write-Progress -Activity "Monitoring AQL Running" -Status "Next Alarm in $i seconds..." -PercentComplete (($waitTimeInSeconds - $i) / $waitTimeInSeconds * 100)
            Start-Sleep -Seconds 1
        }
        Write-Progress -Activity "AQL Monitoring Conducted" -Completed

        Write-Host "`n [!] ALARM RINGING! PLEASE ENTER THE THREAT STATUS [!]" -ForegroundColor Red -BackgroundColor Yellow
        
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
                Write-Host "`n Enter Current Threat Status:" -ForegroundColor Yellow
                Write-Host "   [C] Critical" -ForegroundColor Red
                Write-Host "   [H] High"     -ForegroundColor Magenta
                Write-Host "   [M] Medium"   -ForegroundColor DarkYellow
                Write-Host "   [L] Low"      -ForegroundColor Green
                
                $inputRaw = Read-Host "`n Pilihan Anda (C/H/M/L atau Critical/High/Medium/Low)"
                
                if (-not [string]::IsNullOrWhiteSpace($inputRaw)) {
                    $severity = $inputRaw.Trim().Substring(0, 1).ToUpper()
                }

                if ($severity -in @('C', 'H', 'M', 'L')) {
                    $validInput = $true
                } else {
                    Write-Host " Pilihan tidak valid! Harap masukkan C, H, M, L atau nama statusnya." -ForegroundColor Red
                }
            }
        }
        finally {
berhasil didapatkan
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

# Remediation
if ($F5Reset){
    routeF5Reset
}

