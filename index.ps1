param(
    [switch]$OperatingSystem
)

#Support
. $PSScriptRoot\Helpers\Banner.ps1
. $PSScriptRoot\Helpers\OperatingSystem.ps1

function showBanner {
    helperBanner
}

showBanner

if ($OperatingSystem){
	helperOperatingSystem
}





