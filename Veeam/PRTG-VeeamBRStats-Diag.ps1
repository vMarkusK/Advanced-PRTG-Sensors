[cmdletbinding()]
param(
    [Parameter(Position=0, Mandatory=$false)]
        [string] $BRHost = "localhost"
)

try {
    $MyModulePath = "C:\Program Files\Veeam\Backup and Replication\Console\"
    $env:PSModulePath = $env:PSModulePath + "$([System.IO.Path]::PathSeparator)$MyModulePath"
    $Module = Get-Module -ListAvailable -Name Veeam.Backup.PowerShell -ErrorAction Stop
}
catch {
    Write-Output "No Module Found"

    Write-Error $_.ToString()
    Write-Error $_.ScriptStackTrace

    Write-Output "<prtg>"
    Write-Output " <error>1</error>"
    Write-Output " <text>User '$($env:USERNAME)' /  Error::  $($_.ToString())</text>"
    Write-Output "</prtg>"

    exit

}

try {
    $MyModulePath = "C:\Program Files\Veeam\Backup and Replication\Console\"
    $env:PSModulePath = $env:PSModulePath + "$([System.IO.Path]::PathSeparator)$MyModulePath"
    Import-Module -Name Veeam.Backup.PowerShell -WarningAction SilentlyContinue -ErrorAction Stop
}
catch {
    Write-Output "Module load Failed"

    Write-Error $_.ToString()
    Write-Error $_.ScriptStackTrace

    Write-Output "<prtg>"
    Write-Output " <error>1</error>"
    Write-Output " <text>User '$($env:USERNAME)' /  Error::  $($_.ToString())</text>"
    Write-Output "</prtg>"

    exit

}

try {
    Connect-VBRServer -Server $BRHost
}
catch {
    Write-Output "Failed to Connect"

    Write-Error $_.ToString()
    Write-Error $_.ScriptStackTrace

    Write-Output "<prtg>"
    Write-Output " <error>1</error>"
    Write-Output " <text>User '$($env:USERNAME)' /  Error::  $($_.ToString())</text>"
    Write-Output "</prtg>"

    exit

}

try {
    Disconnect-VBRServer
}
catch {
    Write-Output "Failed to Disconnect"

    Write-Error $_.ToString()
    Write-Error $_.ScriptStackTrace

    Write-Output "<prtg>"
    Write-Output " <error>1</error>"
    Write-Output " <text>User '$($env:USERNAME)' /  Error::  $($_.ToString())</text>"
    Write-Output "</prtg>"

    exit

}

Write-Output "<prtg>"
Write-Output "<result>"
Write-Output "  <channel>Status/channel>"
Write-Output "  <value>Success</value>"
Write-Output "  <showChart>0</showChart>"
Write-Output "  <showTable>0</showTable>"
Write-Output "</result>"
Write-Output "</prtg>"