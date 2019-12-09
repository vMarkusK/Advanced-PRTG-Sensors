<#
        .SYNOPSIS
        PRTG Veeam Advanced Sensor

        .DESCRIPTION
        Advanced Sensor will Report Statistics about Backups during last 24 Hours and Actual Repository usage.

        .PARAMETER PSRemote
        Switch to use PSRemoting instead of locally installed VeeamPSSnapin.
        Use "Get-Help about_remote_requirements" for more information

        .EXAMPLE
        PRTG-VeeamBRStats.ps1 -BRHost veeam01.lan.local

        .EXAMPLE
        PRTG-VeeamBRStats.ps1 -BRHost veeam01.lan.local -reportmode "Monthly" -repoCritical 80 -repoWarn 70 -Debug

        .EXAMPLE
        PRTG-VeeamBRStats.ps1 -BRHost veeam01.lan.local -reportmode "Monthly" -repoCritical 80 -repoWarn 70 -selChann "BR"

        .Notes
        NAME:  PRTG-VeeamBRStats.ps1
        LASTEDIT: 02/08/2018
        VERSION: 1.8
        KEYWORDS: Veeam, PRTG

        CREDITS:
        Thanks to Shawn, for creating an awsome Reporting Script:
        http://blog.smasterson.com/2016/02/16/veeam-v9-my-veeam-report-v9-0-1/

        Thanks to Bernd Leinfelder for the Scalout Repository part!
        https://github.com/berndleinfelder

        Thanks to Guy Zuercher for the Endpoint Backup part and a lot of other enhancmeents!
        https://github.com/gzuercher

        .Link
        http://mycloudrevolution.com/


 #>
#Requires -Version 3

[cmdletbinding()]
param(
    [Parameter(Position=0, Mandatory=$false)]
        [string] $BRHost = "localhost",
    [Parameter(Position=1, Mandatory=$false)]
        $reportMode = "24", # Weekly, Monthly as String or Hour as Integer
    [Parameter(Position=2, Mandatory=$false)]
        $repoCritical = 10,
    [Parameter(Position=3, Mandatory=$false)]
        $repoWarn = 20,
    [Parameter(Position=4, Mandatory=$false)]
        $selChann = "BCRE", # Inital channel selection
    [Parameter(Position=5, Mandatory=$false)]
         [switch] $PSRemote
)

$includeBackup = $selChann.Contains("B")
$includeCopy = $selChann.Contains("C")
$includeRepl = $selChann.Contains("R")
$includeEP = $selChann.Contains("E")

# Disable output of warning to prevent Veeam PS quirks
$WarningPreference = "SilentlyContinue"

# Activate debug output if Verbose
if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {
    $DebugPreference = 'Continue'
}

# Catch all unhadled errors and close Pssession to avoid this issue:
# Thanks for https://github.com/klmj for the idea
# http://www.checkyourlogs.net/?p=54583

trap{
    if($RemoteSession){Remove-PSSession -Session $RemoteSession}
    Disconnect-VBRServer -ErrorAction SilentlyContinue

    Write-Error $_.ToString()
    Write-Error $_.ScriptStackTrace

    Write-Output "<prtg>"
    Write-Output " <error>1</error>"
    Write-Output " <text>$($_.ToString())</text>"
    Write-Output "</prtg>"

    Exit
}

#region: Start Load VEEAM Snapin (in local or remote session)

if ($PSRemote) {
    # Remoting on VBR server

    $RemoteSession = New-PSSession -Authentication Kerberos -ComputerName $BRHost
    if (-not $RemoteSession){throw "Cannot open remote session on : $($BRHost)"}

    # Loading PSSnapin then retrieve commands
    Invoke-Command -Session $RemoteSession -ScriptBlock {Add-PSSnapin VeeamPSSnapin; $WarningPreference = "SilentlyContinue"} -ErrorAction Stop # muting warning about powershell version
    Import-PSSession -Session $RemoteSession -Module VeeamPSSnapin -ErrorAction Stop | Out-Null
} else {

    if (!(Get-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue)) {
        try {
            Add-PSSnapin -PassThru VeeamPSSnapIn -ErrorAction Stop | Out-Null
        }
        catch {
            throw "Failed to load VeeamPSSnapIn"
        }
    }
}
#endregion



#region: Functions

# Big thanks to Shawn, creating an awsome Reporting Script:
# http://blog.smasterson.com/2016/02/16/veeam-v9-my-veeam-report-v9-0-1/

Function Get-vPCRepoInfo {
[CmdletBinding()]
    param (
        [Parameter(Position=0, ValueFromPipeline=$true)]
        [PSObject[]]$Repository
    )
    Begin {
        $outputAry = @()
        Function New-RepoObject {param($name, $repohost, $path, $free, $total)
        $repoObj = New-Object -TypeName PSObject -Property @{
            Target = $name
            RepoHost = $repohost
                        Storepath = $path
                        StorageFree = [Math]::Round([Decimal]$free/1GB,2)
                        StorageTotal = [Math]::Round([Decimal]$total/1GB,2)
                        FreePercentage = [Math]::Round(($free/$total)*100)
            }
        Return $repoObj | Select-Object Target, RepoHost, Storepath, StorageFree, StorageTotal, FreePercentage
        }
    }
    Process {
        Foreach ($r in $Repository) {
            # Refresh Repository Size Info
            try {
                if ($PSRemote) {
                    $SyncSpaceCode = {
                        param($RepositoryName);
                        [Veeam.Backup.Core.CBackupRepositoryEx]::SyncSpaceInfoToDb((Get-VBRBackupRepository -Name $RepositoryName), $true)
                    }

                    Invoke-Command -Session $RemoteSession -ScriptBlock $SyncSpaceCode -ArgumentList $r.Name
                } else {
                    [Veeam.Backup.Core.CBackupRepositoryEx]::SyncSpaceInfoToDb($r, $true)
                }

            }
            catch {
                Write-Debug "SyncSpaceInfoToDb Failed"
                Write-Error $_.ToString()
                Write-Error $_.ScriptStackTrace
            }
            If ($r.HostId -eq "00000000-0000-0000-0000-000000000000") {
                $HostName = ""
            }
            Else {
                $HostName = $(Get-VBRServer | Where-Object {$_.Id -eq $r.HostId}).Name.ToLower()
            }

            if ($PSRemote) {
            # When veeam commands are invoked remotly they are serialized during transfer. The info property become not object but string.
            # To gather the info following construction should be used
                $r.info = Invoke-Command -Session $RemoteSession -HideComputerName -ScriptBlock {
                    param($RepositoryName);
                    (Get-VBRBackupRepository -Name $RepositoryName).info
                } -ArgumentList $r.Name
            }

            Write-Debug $r.Info
            $outputObj = New-RepoObject $r.Name $Hostname $r.Path $r.info.CachedFreeSpace $r.Info.CachedTotalSpace
        }
        $outputAry += $outputObj
    }
    End {
        $outputAry
    }
}
#endregion

#region: Start BRHost Connection
Write-Debug "Starting to Process Connection to $BRHost ..."
$OpenConnection = (Get-VBRServerSession).Server
if($OpenConnection -eq $BRHost) {
    Write-Debug "BRHost is Already Connected..."
} elseif ($null -eq $OpenConnection) {
    Write-Debug "Connecting BRHost..."
    try {
        Connect-VBRServer -Server $BRHost
    }
    catch {
        Throw "Failed to connect to Veeam BR Host"
    }
} else {
    Write-Debug "Disconnection actual BRHost..."
    Disconnect-VBRServer
    Write-Debug "Connecting new BRHost..."

    try {
        Connect-VBRServer -Server $BRHost
    }
    catch {
        Throw "Failed to connect to Veeam BR Host"
    }
}

$NewConnection = (Get-VBRServerSession).Server
if ($null -eq $NewConnection) {
    Throw "Failed to connect to Veeam BR Host"
}
#endregion

#region: Convert mode (timeframe) to hours
If ($reportMode -eq "Monthly") {
        $HourstoCheck = 720
} Elseif ($reportMode -eq "Weekly") {
        $HourstoCheck = 168
} Else {
        $HourstoCheck = $reportMode
}
#endregion

#region: Collect and filter Repos
[Array]$AllRepos = Get-VBRBackupRepository | Where-Object {$_.Type -notmatch "SanSnapshotOnly"}    # Get all Repositories Except SAN
[Array]$CloudRepos = $AllRepos | Where-Object {$_.Type -match "Cloud"}    # Get all Cloud Repositories
[Array]$repoList = $AllRepos | Where-Object {$_.Type -notmatch "Cloud"}    # Get all Repositories Except SAN and Cloud
<#
Thanks to Bernd Leinfelder for the Scalouts Part!
https://github.com/berndleinfelder
#>
[Array]$scaleouts = Get-VBRBackupRepository -scaleout
if ($scaleouts) {
    foreach ($scaleout in $scaleouts) {
        $extents = Get-VBRRepositoryExtent -Repository $scaleout
        foreach ($ex in $extents) {
            $repoList = $repoList + $ex.repository
        }
    }
}
#endregion

#region: Collect and filter Sessions
$allSesh = Get-VBRBackupSession         # Get all Sessions (Backup/BackupCopy/Replica)
$allEPSesh =  Get-VBREPSession          # Get all Sessions of Endpoint Backups
$SessionObject = [PSCustomObject] @{ }  # Filled for debug option
#endregion

Write-Output "<prtg>"

#region: Backup Jobs
if ($includeBackup) {
    $seshListBk = @($allSesh | Where-Object{($_.CreationTime -ge (Get-Date).AddHours(-$HourstoCheck)) -and $_.JobType -eq "Backup"})           # Gather all Backup sessions within timeframe
    $TotalBackupTransfer = 0
    $TotalBackupRead = 0
    $seshListBk | ForEach-Object{$TotalBackupTransfer += $([Math]::Round([Decimal]$_.Progress.TransferedSize/1GB, 0))}
    $seshListBk | ForEach-Object{$TotalBackupRead += $([Math]::Round([Decimal]$_.Progress.ReadSize/1GB, 0))}
    $successSessionsBk = @($seshListBk | Where-Object{$_.Result -eq "Success"})
    $warningSessionsBk = @($seshListBk | Where-Object{$_.Result -eq "Warning"})
    $failsSessionsBk = @($seshListBk | Where-Object{$_.Result -eq "Failed"})
    $runningSessionsBk = @($allSesh | Where-Object{$_.State -eq "Working" -and $_.JobType -eq "Backup"})
    $failedSessionsBk = @($seshListBk | Where-Object{($_.Result -eq "Failed") -and ($_.WillBeRetried -ne "True")})

    $Count = $successSessionsBk.Count
    Write-Output "<result>"
                "  <channel>Successful-Backups</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "</result>"
    $Count = $warningSessionsBk.Count
    Write-Output "<result>"
                "  <channel>Warning-Backups</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "  <LimitMaxWarning>0</LimitMaxWarning>"
                "  <LimitMode>1</LimitMode>"
                "</result>"
    $Count = $failsSessionsBk.Count
    Write-Output "<result>"
                "  <channel>Failes-Backups</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "  <LimitMaxError>0</LimitMaxError>"
                "  <LimitMode>1</LimitMode>"
                "</result>"
    $Count = $failedSessionsBk.Count
    Write-Output "<result>"
                "  <channel>Failed-Backups</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "  <LimitMaxError>0</LimitMaxError>"
                "  <LimitMode>1</LimitMode>"
                "</result>"
    $Count = $runningSessionsBk.Count
    Write-Output "<result>"
                "  <channel>Running-Backups</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "</result>"
    Write-Output "<result>"
                "  <channel>TotalBackupRead</channel>"
                "  <value>$TotalBackupRead</value>"
                "  <unit>Custom</unit>"
                "  <customUnit>GB</customUnit>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "</result>"
    Write-Output "<result>"
                "  <channel>TotalBackupTransfer</channel>"
                "  <value>$TotalBackupTransfer</value>"
                "  <unit>Custom</unit>"
                "  <customUnit>GB</customUnit>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "</result>"

    $SessionObject | Add-Member -MemberType NoteProperty -Name "Successful Backups" -Value $successSessionsBk.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Warning Backups" -Value $warningSessionsBk.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Failes Backups" -Value $failsSessionsBk.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Failed Backups" -Value $failedSessionsBk.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Running Backups" -Value $runningSessionsBk.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Total Backup Transfer" -Value $TotalBackupTransfer
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Total Backup Read" -Value $TotalBackupRead
}
#endregion:

#region: Copy Jobs
if ($includeCopy) {
    $seshListBkc = @($allSesh | Where-Object{($_.CreationTime -ge (Get-Date).AddHours(-$HourstoCheck)) -and $_.JobType -eq "BackupSync"})      # Gather all BackupCopy sessions within timeframe
    $successSessionsBkC = @($seshListBkC | Where-Object{$_.Result -eq "Success"})
    $warningSessionsBkC = @($seshListBkC | Where-Object{$_.Result -eq "Warning"})
    $failsSessionsBkC = @($seshListBkC | Where-Object{$_.Result -eq "Failed"})
    $runningSessionsBkC = @($allSesh | Where-Object{$_.State -eq "Working" -and $_.JobType -eq "BackupSync"})
    $IdleSessionsBkC = @($allSesh | Where-Object{$_.State -eq "Idle" -and $_.JobType -eq "BackupSync"})
    $failedSessionsBkC = @($seshListBkC | Where-Object{($_.Result -eq "Failed") -and ($_.WillBeRetried -ne "True")})
    $Count = $successSessionsBkC.Count
    Write-Output "<result>"
                "  <channel>Successful-BackupCopys</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "</result>"
    $Count = $warningSessionsBkC.Count
    Write-Output "<result>"
                "  <channel>Warning-BackupCopys</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "  <LimitMaxWarning>0</LimitMaxWarning>"
                "  <LimitMode>1</LimitMode>"
                "</result>"
    $Count = $failsSessionsBkC.Count
    Write-Output "<result>"
                "  <channel>Failes-BackupCopys</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "  <LimitMaxError>0</LimitMaxError>"
                "  <LimitMode>1</LimitMode>"
                "</result>"
    $Count = $failedSessionsBkC.Count
    Write-Output "<result>"
                "  <channel>Failed-BackupCopys</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "  <LimitMaxError>0</LimitMaxError>"
                "  <LimitMode>1</LimitMode>"
                "</result>"
    $Count = $runningSessionsBkC.Count
    Write-Output "<result>"
                "  <channel>Running-BackupCopys</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "</result>"
    $Count = $IdleSessionsBkC.Count
    Write-Output "<result>"
                "  <channel>Idle-BackupCopys</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "</result>"

    $SessionObject | Add-Member -MemberType NoteProperty -Name "Warning BackupCopys" -Value $warningSessionsBkC.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Failes BackupCopys" -Value $failsSessionsBkC.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Failed BackupCopys" -Value $failedSessionsBkC.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Running BackupCopys" -Value $runningSessionsBkC.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Idle BackupCopys" -Value $IdleSessionsBkC.Count
}
#endregion:

#region: Replication Jobs
if ($includeRepl) {
    $seshListRepl = @($allSesh | Where-Object{($_.CreationTime -ge (Get-Date).AddHours(-$HourstoCheck)) -and $_.JobType -eq "Replica"})        # Gather all Replication sessions within timeframe
    $successSessionsRepl = @($seshListRepl | Where-Object{$_.Result -eq "Success"})
    $warningSessionsRepl = @($seshListRepl | Where-Object{$_.Result -eq "Warning"})
    $failsSessionsRepl = @($seshListRepl | Where-Object{$_.Result -eq "Failed"})
    $runningSessionsRepl = @($allSesh | Where-Object{$_.State -eq "Working" -and $_.JobType -eq "Replica"})
    $failedSessionsRepl = @($seshListRepl | Where-Object{($_.Result -eq "Failed") -and ($_.WillBeRetried -ne "True")})

    $Count = $successSessionsRepl.Count
    Write-Output "<result>"
                "  <channel>Successful-Replications</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "</result>"
    $Count = $warningSessionsRepl.Count
    Write-Output "<result>"
                "  <channel>Warning-Replications</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "  <LimitMaxWarning>0</LimitMaxWarning>"
                "  <LimitMode>1</LimitMode>"
                "</result>"
    $Count = $failsSessionsRepl.Count
    Write-Output "<result>"
                "  <channel>Failes-Replications</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "  <LimitMaxError>0</LimitMaxError>"
                "  <LimitMode>1</LimitMode>"
                "</result>"
    $Count = $failedSessionsRepl.Count
    Write-Output "<result>"
                "  <channel>Failed-Replications</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "  <LimitMaxError>0</LimitMaxError>"
                "  <LimitMode>1</LimitMode>"
                "</result>"
    $Count = $runningSessionsRepl.Count
    Write-Output "<result>"
                "  <channel>Running-Replications</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "</result>"
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Successful Replications" -Value $successSessionsRepl.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Warning Replications" -Value $warningSessionsRepl.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Failes Replications" -Value $failsSessionsRepl.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Failed Replications" -Value $failedSessionsRepl.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Running Replications" -Value $RunningSessionsRepl.Count
}
#endregion:

#region: Endpoint Jobs
if ($includeEP) {
    $seshListEP = @($allEPSesh | Where-Object{($_.CreationTime -ge (Get-Date).AddHours(-$HourstoCheck))}) # Gather all Endpoint sessions within timeframe
    $successSessionsEP = @($seshListEP | Where-Object{$_.Result -eq "Success"})
    $warningSessionsEP = @($seshListEP | Where-Object{$_.Result -eq "Warning"})
    $failsSessionsEP = @($seshListEP | Where-Object{$_.Result -eq "Failed"})
    $runningSessionsEP = @($allEPSesh | Where-Object{$_.State -eq "Working"})

    $Count = $successSessionsEP.Count
    Write-Output "<result>"
                "  <channel>Successful-Endpoints</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "</result>"
    $Count = $warningSessionsEP.Count
    Write-Output "<result>"
                "  <channel>Warning-Endpoints</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "  <LimitMaxWarning>0</LimitMaxWarning>"
                "  <LimitMode>1</LimitMode>"
                "</result>"
    $Count = $failsSessionsEP.Count
    Write-Output "<result>"
                "  <channel>Failes-Endpoints</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "  <LimitMaxError>0</LimitMaxError>"
                "  <LimitMode>1</LimitMode>"
                "</result>"
    $Count = $runningSessionsEP.Count
    Write-Output "<result>"
                "  <channel>Running-Endpoints</channel>"
                "  <value>$Count</value>"
                "  <showChart>1</showChart>"
                "  <showTable>1</showTable>"
                "</result>"

    $SessionObject | Add-Member -MemberType NoteProperty -Name "Seccessful Endpoints" -Value $successSessionsEP.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Warning Endpoints" -Value $warningSessionsEP.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Failes Endpoints" -Value $failsSessionsEP.Count
    $SessionObject | Add-Member -MemberType NoteProperty -Name "Running Endpoints" -Value $runningSessionsEP.Count
}
#endregion:

#region: Repository
$RepoReport = $repoList | Get-vPCRepoInfo | Select-Object   @{Name="Repository Name"; Expression = {$_.Target}},
                                                            @{Name="Host"; Expression = {$_.RepoHost}},
                                                            @{Name="Path"; Expression = {$_.Storepath}},
                                                            @{Name="Free (GB)"; Expression = {$_.StorageFree}},
                                                            @{Name="Total (GB)"; Expression = {$_.StorageTotal}},
                                                            @{Name="Free (%)"; Expression = {$_.FreePercentage}},
                                                            @{Name="Status"; Expression = {
                                                            If ($_.FreePercentage -lt $repoCritical) {"Critical"}
                                                            ElseIf ($_.FreePercentage -lt $repoWarn) {"Warning"}
                                                            ElseIf ($_.FreePercentage -eq "Unknown") {"Unknown"}
                                                            Else {"OK"}}} | `
                                                            Sort-Object "Repository Name"

foreach ($Repo in $RepoReport){
$Name = "REPO - " + $Repo."Repository Name"
$Free = $Repo."Free (%)"
Write-Output "<result>"
            "  <channel>$Name</channel>"
            "  <value>$Free</value>"
            "  <unit>Percent</unit>"
            "  <showChart>1</showChart>"
            "  <showTable>1</showTable>"
            "  <LimitMinWarning>$repoWarn</LimitMinWarning>"
            "  <LimitMinError>$repoCritical</LimitMinError>"
            "  <LimitMode>1</LimitMode>"
            "</result>"
}
#endregion

if($RemoteSession){Remove-PSSession -Session $RemoteSession}
Write-Output "</prtg>"

#region: Debug
if ($DebugPreference -eq "Inquire") {
        $RepoReport | Format-Table * -Autosize
        $SessionReport += $SessionObject
        $SessionReport
}
#endregion

# eof
