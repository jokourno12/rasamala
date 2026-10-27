. $PSScriptRoot\..\Middleware\MiddlewareF5Reset.ps1
. $PSScriptRoot\..\Controllers\Remediations\ControlCrashStabilization.ps1

function routeF5Reset{
    middlewareF5Reset
}

function routeCrashStabilization{
    controlCrashStabilzation
}