. $PSScriptRoot\..\Controllers\RecordKeeping\ControlRecordKeeping.ps1
. $PSScriptRoot\..\Controllers\RecordKeeping\ControlLog.ps1

function routeRecordKeeping{
    controlRecordKeeping
}

function routeLog{
    controlLog
}