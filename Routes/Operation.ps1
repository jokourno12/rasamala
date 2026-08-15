. $PSScriptRoot\..\Controllers\Operations\ControlEndpointMetric.ps1
. $PSScriptRoot\..\Controllers\Operations\ControlAqlMonitoring.ps1
. $PSScriptRoot\..\Controllers\Operations\ControlBrowserIsolation.ps1


function routeEndpointMetric{
    controlEndpointMetric
}

function routeAqlMonitoring{
    controlAqlMonitoring
}

function routeBrowserIsolation{
    controlBrowserIsolation
}