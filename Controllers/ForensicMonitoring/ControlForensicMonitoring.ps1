. $PSScriptRoot\ControlEndpointMetric.ps1
. $PSScriptRoot\ControlAqlMonitoring.ps1

function controlForensicMonitoring {
    Write-Host "`n [INIT] Preparing Live Background Telemetry..." -ForegroundColor Cyan

    $SharedState = [hashtable]::Synchronized(@{
        KeepRunning   = $true
        LastError     = $null
        TelemetryReady = $false
    })

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $runspace

    [void]$ps.AddScript({
        param($state, $scriptFolder)
        try {
            $metricScript = Join-Path -Path $scriptFolder -ChildPath 'ControlEndpointMetric.ps1'
            . $metricScript
            $state.TelemetryReady = $true
            controlEndpointMetric -SharedState $state
        }
        catch {
            $state.LastError = $_.Exception.Message
            $state.KeepRunning = $false
        }
    }).AddArgument($SharedState).AddArgument($PSScriptRoot)

    $asyncHandle = $ps.BeginInvoke()

    # Tunggu maksimal 3 detik sampai background script benar-benar siap (lebih adaptif daripada hardcode sleep)
    $waitMs = 0
    while (-not $SharedState.TelemetryReady -and $SharedState.KeepRunning -and $waitMs -lt 3000) {
        Start-Sleep -Milliseconds 100
        $waitMs += 100
    }

    if ($SharedState.LastError) {
        Write-Host " [ERR] Background Telemetry failed: $($SharedState.LastError)" -ForegroundColor Red
    }
    else {
        Write-Host " [OK] Background Telemetry Active. Launching AQL..." -ForegroundColor Green
    }

    try {
        controlAqlMonitoring -SharedState $SharedState
    }
    finally {
        # Blok ini DIJAMIN tetap jalan meskipun user menekan Ctrl+C atau terjadi error
        $SharedState.KeepRunning = $false

        # Beri waktu maksimal 2 detik agar loop background berhenti secara bersih (graceful shutdown)
        if ($asyncHandle -and -not $asyncHandle.IsCompleted) {
            [void]$asyncHandle.AsyncWaitHandle.WaitOne(2000)
        }

        if ($ps) {
            $ps.Stop()
            $ps.Dispose()
        }
        if ($runspace) {
            $runspace.Close()
            $runspace.Dispose()
        }
    }
}