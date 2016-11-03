<#
    .SYNOPSIS
    PRTG Advanced Scheduled Task Sensor
  
    .DESCRIPTION
    This Advanced Sensor will report Task Statistics.
        
    .EXAMPLE
    PRTG-ScheduledTask.ps1 -ComputerName myComputer.lan.local -TaskName "myTaskName"

    .Notes
    NAME:  PRTG-ScheduledTask.ps1
    AUTHOR: Markus Kraus
    LASTEDIT: 09/14/2016
    VERSION: 1.1
    KEYWORDS: PRTG, Windows, Schedule Task
   
    .Link
    http://mycloudrevolution.com/

    .Link
    https://vater.cloud
 
 #Requires PS -Version 3.0  
 #>
[cmdletbinding()]
param(
    [Parameter(Position=0, Mandatory=$false)]
    	[string]$ComputerName = $env:COMPUTERNAME,
	[Parameter(Position=1, Mandatory=$true)]
        [string]$TaskName
)

#region: Definitions
$Date = Get-Date -Format G
#endregion

#region: Functions
## Source: https://gallery.technet.microsoft.com/scriptcenter/Get-Scheduled-tasks-from-3a377294
function Get-AllTaskSubFolders {
    [cmdletbinding()]
    param (
        # Set to use $Schedule as default parameter so it automatically list all files
        # For current schedule object if it exists.
        $FolderRef = $Schedule.getfolder("\")
    )
    if ($FolderRef.Path -eq '\') {
        $FolderRef
    }
    if (-not $RootFolder) {
        $ArrFolders = @()
        if(($Folders = $folderRef.getfolders(1))) {
            $Folders | ForEach-Object {
                $ArrFolders += $_
                if($_.getfolders(1)) {
                    Get-AllTaskSubFolders -FolderRef $_
                }
            }
        }
        $ArrFolders
    }
}
#endregion Functions

#region: Create Object
try {
    Write-Verbose "Creating Object..."
	$Schedule = New-Object -ComObject 'Schedule.Service'
} catch {
	Write-Warning "Schedule.Service COM Object not found, this script requires this object"
	return
}
#endregion

#region: Connect to Comuter and get Task Folders
Write-Verbose "Connect to Comuter and get Task Folders..."
$Schedule.connect($ComputerName) 
$AllFolders = Get-AllTaskSubFolders
#endregion

#region: Get Task Details
Write-Verbose "Get Task Details..."
[Array] $myTask = $AllFolders.GetTasks(1) | Where-Object {$_.name -eq $TaskName} | Foreach-Object {
	        New-Object -TypeName PSCustomObject -Property @{
	            'Name' = $_.name
                'Path' = $_.path
                'State' = switch ($_.State) {
                    0 {'Unknown'}
                    1 {'Disabled'}
                    2 {'Queued'}
                    3 {'Ready'}
                    4 {'Running'}
                    Default {'Unknown'}
                }
                'Enabled' = $_.enabled
                'LastRunTime' = $_.lastruntime
                'LastRunInHours' = [math]::round($(New-TimeSpan -Start $([datetime]$_.lastruntime) -End $Date).TotalHours,0)
                'LastTaskResult' = $_.lasttaskresult
                'NumberOfMissedRuns' = $_.numberofmissedruns
                'NextRunTime' = $_.nextruntime
                'ComputerName' = $Schedule.TargetServer
            }
    }
if ($myTask.Length -gt 1) {
        Write-Error "More than one Task fount. Exiting..."
        Exit 1
}
#endregion

#region: XML Output
Write-Verbose "XML Output..."
if ($myTask) {
    Write-Host "<prtg>" 
    foreach ($Object in $myTask){
        $LastRunInHours = $Object.LastRunInHours
        $LastTaskResult = $Object.LastTaskResult
        $LastRunTime    = $Object.LastRunTime
        $NextRunTime    = $Object.NextRunTime
        Write-Host "<result>"
                    "<channel>LastRunInHours</channel>"
                    "<value>$LastRunInHours</value>"
                    "<Unit>TimeHours</Unit>"
                    "<showChart>1</showChart>"
                    "<showTable>1</showTable>"
                    "</result>" 
        Write-Host "<result>"
                    "<channel>LastTaskResult</channel>"
                    "<value>$LastTaskResult</value>"
                    "<DecimalMode>All</DecimalMode>"
                    "<showChart>1</showChart>"
                    "<showTable>1</showTable>"
                    "<LimitMinError>0</LimitMinError>"
                    "<LimitMaxError>0</LimitMaxError>"
                    "<LimitMode>1</LimitMode>"
                    "</result>" 
            }
    Write-Host "</prtg>" 
}
else {
    Write-Error "No Task with Name: $TaskName found. Exiting..."
    Exit 1
}
#endregion

#region: Debug
if ($DebugPreference -eq "Inquire") {
	$myTask | Select-Object ComputerName, Name, Path, Enabled, State, LastRunTime,  NextRunTime,  LastRunInHours, LastTaskResult, NumberOfMissedRuns | ft * -Autosize
}
#endregion
