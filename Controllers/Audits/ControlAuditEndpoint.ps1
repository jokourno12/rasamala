function controlAuditEndpoint{
    $Global:HasilAudit = & {
        routeProcessorStressTesting
        routeCheckingUpdateSystem
        routeStoragePerformanceTesting
        routeNetworkPerimeterTesting
        routeNetworkCoverageTesting
        routeCheckingRemoteSession
    } *>&1
    
    $cleanData = $Global:HasilAudit | Where-Object { $_ -is [PSCustomObject] }

    $jsonResult = $cleanData | ConvertTo-Json -Depth 4
    return $jsonResult
}