. $PSScriptRoot\..\Controllers\Audits\ControlProcessorStressTesting.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingUpdateSystem.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlStoragePerformanceTesting.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlNetworkPerimeterTesting.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlNetworkCoverageTesting.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingRemoteSession.ps1

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
    controlCheckingRemoteSession
}