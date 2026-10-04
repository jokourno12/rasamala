. $PSScriptRoot\..\Controllers\Audits\ControlProcessorStressTesting.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingUpdateSystem.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlStoragePerformanceTesting.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingFirewall.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingNetworkConnection.ps1
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

function routeCheckingFirewall{
    controlCheckingFirewall
}

function routeCheckingNetworkConnection{
    controlCheckingNetworkConnection
}

$auditResults = [ordered]@{}

function routeCheckingRemoteSession{
    controlCheckingRemoteSession
}