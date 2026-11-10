. $PSScriptRoot\..\Controllers\BackupStrategy\ControlBackupStrategy.ps1
. $PSScriptRoot\..\Controllers\BackupStrategy\ControlSnapshot.ps1

function routeBackupStrategy{
    controlBackupStrategy
}

function routeSnapshot{
    controlSnapshot
}