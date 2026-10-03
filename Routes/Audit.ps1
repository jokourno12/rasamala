. $PSScriptRoot\..\Controllers\Audits\ControlStressTesting.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingUpdateSystem.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingDiskEncryption.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingFirewall.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingNetworkConnection.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingRemoteSession.ps1

function routeStressTesting{
    controlStressTesting
}

function routeCheckingUpdateSystem{
    controlCheckingUpdateSystem
}

function routeCheckingDiskEncryption{
    controlCheckingDiskEncryption
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