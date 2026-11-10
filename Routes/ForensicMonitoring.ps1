. $PSScriptRoot\..\Controllers\ForensicMonitoring\ControlForensicMonitoring.ps1
. $PSScriptRoot\..\Controllers\ForensicMonitoring\ControlEndpointMetric.ps1
. $PSScriptRoot\..\Controllers\ForensicMonitoring\ControlAqlMonitoring.ps1

function routeForensicMonitoring{
    controlForensicMonitoring
}

function routeEndpointMetric{
    controlEndpointMetric
}

function routeAqlMonitoring{
    controlAqlMonitoring
}