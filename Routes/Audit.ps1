. $PSScriptRoot\..\Helpers\OperatingSystem.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingUpdateSystem.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingDiskEncryption.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingFirewall.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingNetworkPorts.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingRemoteSession.ps1
. $PSScriptRoot\..\Controllers\Audits\ControlCheckingOutboundConnection.ps1

function routeOperatingSystem{
    helperOperatingSystem
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

function routeCheckingNetworkPorts{
    controlCheckingNetworkPorts
}

$auditResults = [ordered]@{}

function routeCheckingRemoteSession{
    controlCheckingRemoteSession
}

function routeCheckingOutboundConnection{
    controlCheckingOutboundConnection
}