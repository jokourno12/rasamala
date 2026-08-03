param(
    [switch]$OperatingSystem,
    [switch]$CheckingUpdateSystem,
    [switch]$CheckingDiskEncryption,
    [switch]$CheckingFirewall,
    [switch]$CheckingNetworkPorts,
    [switch]$CheckingRemoteSession,
    [switch]$CheckingOutboundConnection,
    [switch]$EndpointMetric,
    [switch]$F5Reset
)

#Support
. $PSScriptRoot\Helpers\Banner.ps1
. $PSScriptRoot\Routes\Audit.ps1
. $PSScriptRoot\Routes\Operation.ps1
. $PSScriptRoot\Routes\Remediation.ps1

function showBanner {
    helperBanner
}

showBanner
# Audit
if ($OperatingSystem){
    routeOperatingSystem
}

if ($CheckingUpdateSystem){
    routeCheckingUpdateSystem
}

if ($CheckingDiskEncryption){
    routeCheckingDiskEncryption
}

if ($CheckingFirewall){
    routeCheckingFirewall
}

if ($CheckingNetworkPorts){
    routeCheckingNetworkPorts
}

if ($CheckingRemoteSession){
    routeCheckingRemoteSession
}

if ($CheckingOutboundConnection){
    routeCheckingOutboundConnection
}

# Operation
if ($EndpointMetric){
    routeEndpointMetric
}

# Remediation
if ($F5Reset){
    routeF5Reset
}

