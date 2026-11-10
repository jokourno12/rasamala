. $PSScriptRoot\..\Controllers\ForensicMonitoring\ControlForensicMonitoring.ps1
. $PSScriptRoot\..\Controllers\ForensicMonitoring\ControlEndpointMetric.ps1
. $PSScriptRoot\..\Controllers\ForensicMonitoring\ControlAqlMonitoring.ps1

function routeForensicMonitoring{
    Write-Host " [DEBUG] Berhasil masuk ke routeForensicMonitoring!" -ForegroundColor Yellow
    controlForensicMonitoring
}

function routeEndpointMetric{
    controlEndpointMetric
}

function routeAqlMonitoring{
    controlAqlMonitoring
}