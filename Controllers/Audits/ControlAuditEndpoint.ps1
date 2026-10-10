function controlAuditEndpoint{
    $Global:HasilAudit = & {
        routeProcessorStressTesting
        routeCheckingUpdateSystem
        routeStoragePerformanceTesting
        routeNetworkPerimeterTesting
        routeNetworkCoverageTesting
        routeCheckingRemoteSession
    } *>&1
    
    $HasilAudit
}