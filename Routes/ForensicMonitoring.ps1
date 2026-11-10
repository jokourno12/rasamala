. $PSScriptRoot\..\Controllers\ForensicMonitoring\ControlEndpointMetric.ps1
. $PSScriptRoot\..\Controllers\ForensicMonitoring\ControlAqlMonitoring.ps1

function routeEndpointMetric{
    controlEndpointMetric
}

function routeAqlMonitoring{
    controlAqlMonitoring
}