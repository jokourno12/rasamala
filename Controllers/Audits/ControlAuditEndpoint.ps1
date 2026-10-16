function controlAuditEndpoint{
    $InformationPreference = 'SilentlyContinue'

    $auditResults = [ordered]@{
        Timestamp          = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        HostName           = $env:COMPUTERNAME
        ProcessorStress    = routeProcessorStressTesting -ReturnData 6>$null
        SystemUpdate       = routeCheckingUpdateSystem -ReturnData 6>$null
        StoragePerformance = routeStoragePerformanceTesting -ReturnData 6>$null
        NetworkPerimeter   = routeNetworkPerimeterTesting -ReturnData 6>$null
        NetworkCoverage    = routeNetworkCoverageTesting -ReturnData 6>$null
        RemoteSession      = routeCheckingRemoteSession -ReturnData 6>$null
    }

    # Output tunggal berbentuk JSON murni
    return ($auditResults | ConvertTo-Json -Depth 5)
}