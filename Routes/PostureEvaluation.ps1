. $PSScriptRoot\..\Controllers\PostureEvaluation\ControlAuditEndpoint.ps1
. $PSScriptRoot\..\Controllers\PostureEvaluation\ControlProcessorStressTesting.ps1
. $PSScriptRoot\..\Controllers\PostureEvaluation\ControlCheckingUpdateSystem.ps1
. $PSScriptRoot\..\Controllers\PostureEvaluation\ControlStoragePerformanceTesting.ps1
. $PSScriptRoot\..\Controllers\PostureEvaluation\ControlNetworkPerimeterTesting.ps1
. $PSScriptRoot\..\Controllers\PostureEvaluation\ControlNetworkCoverageTesting.ps1
. $PSScriptRoot\..\Controllers\PostureEvaluation\ControlCheckingRemoteSession.ps1
. $PSScriptRoot\..\Helpers\HelperDataEpeat.ps1

function routeAuditEndpoint{
    controlAuditEndpoint
}

function routeProcessorStressTesting{
    controlProcessorStressTesting
}

function routeCheckingUpdateSystem{
    controlCheckingUpdateSystem
}

function routeStoragePerformanceTesting{
    controlStoragePerformanceTesting
}

function routeNetworkPerimeterTesting{
    controlNetworkPerimeterTesting
}

function routeNetworkCoverageTesting{
    controlNetworkCoverageTesting
}

$auditResults = [ordered]@{}

function routeCheckingRemoteSession{
    helperDataEpeat
    controlCheckingRemoteSession
}