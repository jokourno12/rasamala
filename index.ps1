[CmdletBinding()]
param(
    [switch]$PostureEvaluation,
        [switch]$ProcessorStressTesting,
        [switch]$CheckingUpdateSystem,
        [switch]$StoragePerformanceTesting,
        [switch]$NetworkPerimeterTesting,
        [switch]$NetworkCoverageTesting,
        [switch]$CheckingRemoteSession,

    [switch]$SecurityControl,
        [switch]$F5Reset,
        [switch]$CrashStabilization,
        [switch]$BrowserIsolation,
        [switch]$JavaScriptRuntime,
        [switch]$BrowserTunnel,

    [switch]$ForensicMonitoring,
        [switch]$EndpointMetric,
        [switch]$AqlMonitoring,

    [switch]$RecordKeeping,
        [switch]$Log,

    [switch]$BackupStrategy,
        [switch]$Snapshot,

    [switch]$SlaInfo,

    # AQL Monitoring
    [ValidateSet(7, 14, 28, 42)]
    [int]$InitialInterval = 7,

    #Isolated Session
    [Parameter(Mandatory=$false)]
    [string]$TargetUrl = "about:blank"
)

. $PSScriptRoot\Config\Windows.ps1
. $PSScriptRoot\Helpers\Banner.ps1
. $PSScriptRoot\Helpers\SlaInfo.ps1
. $PSScriptRoot\Routes\PostureEvaluation.ps1
. $PSScriptRoot\Routes\SecurityControl.ps1
. $PSScriptRoot\Routes\ForensicMonitoring.ps1
. $PSScriptRoot\Routes\RecordKeeping.ps1
. $PSScriptRoot\Routes\BackupStrategy.ps1

function showBanner {
    helperBanner
}

showBanner
# PostureEvaluation
if ($PostureEvaluation){
    routePostureEvaluation
}

if ($ProcessorStressTesting){
    routeProcessorStressTesting
}

if ($CheckingUpdateSystem){
    routeCheckingUpdateSystem
}

if ($StoragePerformanceTesting){
    routeStoragePerformanceTesting
}

if ($NetworkPerimeterTesting){
    routeNetworkPerimeterTesting
}

if ($NetworkCoverageTesting){
    routeNetworkCoverageTesting
}

if ($CheckingRemoteSession){
    routeCheckingRemoteSession
}

# SecurityControl
if ($SecurityControl){
    routeSecurityControl
}

if ($F5Reset){
    routeF5Reset
}

if ($CrashStabilization){
    routeCrashStabilization
}

if ($BrowserIsolation){
    routeBrowserIsolation
}

if ($JavaScriptRuntime){
    routeJavaScriptRuntime
}

if ($BrowserTunnel){
    routeBrowserTunnel
}

if ($SlaInfo){
    helperSlaInfo
}

# ForensicMonitoring
if ($ForensicMonitoring){
    routeForensicMonitoring
}

if ($EndpointMetric){
    routeEndpointMetric
}

if ($AqlMonitoring){
    routeAqlMonitoring
}

# RecordKeeping
if ($RecordKeeping){
    routeRecordKeeping
}

if ($Log){
    routeLog
}

# BackupStrategy
if ($BackupStrategy){
    routeBackupStrategy
}

if ($Snapshot){
    routeSnapshot
}
