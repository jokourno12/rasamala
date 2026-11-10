. $PSScriptRoot\..\Middleware\MiddlewareF5Reset.ps1
. $PSScriptRoot\..\Controllers\SecurityControl\ControlCrashStabilization.ps1
. $PSScriptRoot\..\Controllers\SecurityControl\ControlSecurityControl.ps1
. $PSScriptRoot\..\Controllers\SecurityControl\ControlBrowserIsolation.ps1
. $PSScriptRoot\..\Controllers\SecurityControl\ControlJavaScriptRuntime.ps1
. $PSScriptRoot\..\Controllers\SecurityControl\ControlBrowserTunnel.ps1

function routeSecurityControl{
    controlSecurityControl
}

function routeBrowserIsolation{
    controlBrowserIsolation
}

function routeJavaScriptRuntime{
    controlJavaScriptRuntime
}

function routeBrowserTunnel{
    controlBrowserTunnel
}

function routeF5Reset{
    middlewareF5Reset
}

function routeCrashStabilization{
    controlCrashStabilization
}