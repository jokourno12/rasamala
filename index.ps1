[CmdletBinding()]
param(
    [switch]$OperatingSystem,
    [switch]$CheckingUpdateSystem,
    [switch]$CheckingDiskEncryption,
    [switch]$CheckingFirewall,
    [switch]$CheckingNetworkPorts,
    [switch]$CheckingRemoteSession,
    [switch]$CheckingOutboundConnection,

    [switch]$EndpointMetric,

    [switch]$AqlMonitoring,
    [switch]$F5Reset,

    [switch]$SlaInfo,

    [ValidateSet(7, 14, 28, 42)]
    [int]$InitialInterval = 7,

    [ValidateSet('All', 'Taspen', 'Pertamina')]
    [string]$Client = 'All'
)

#Support
. $PSScriptRoot\Helpers\Banner.ps1
. $PSScriptRoot\Helpers\SlaInfo.ps1
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

if ($AqlMonitoring){
    routeAqlMonitoring
}

# Remediation
if ($F5Reset){
    routeF5Reset
}

# Information
if ($SlaInfo){
    helperSlaInfo -Client $Client
    exit
}