. $PSScriptRoot\ControlEndpointMetric.ps1
. $PSScriptRoot\ControlAqlMonitoring.ps1

function controlForensicMonitoring {
    Write-Host "`n [INIT] Preparing Live Background Telemetry..." -ForegroundColor Cyan

    $SharedState = [hashtable]::Synchronized(@{})
    $SharedState.KeepRunning = $true

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.Open()
    $ps = [powershell]::Create()
    $ps.Runspace = $runspace

    $ps.AddScript({
        param($state, $scriptFolder)
        . "$scriptFolder\ControlEndpointMetric.ps1"
        controlEndpointMetric -SharedState $state
    }).AddArgument($SharedState).AddArgument($PSScriptRoot)

    $null = $ps.BeginInvoke()

    Write-Host " [OK] Background Telemetry Active. Launching AQL..." -ForegroundColor Green
    Start-Sleep -Seconds 2 

    controlAqlMonitoring -SharedState $SharedState

    $SharedState.KeepRunning = $false
    $runspace.Close()
    $runspace.Dispose()
}