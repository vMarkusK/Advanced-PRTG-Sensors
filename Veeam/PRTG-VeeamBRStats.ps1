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
        LASTEDIT: 2021/03/16
        VERSION: 2.0.1
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

# Disable output of warning to prevent Veeam PS quirks
$WarningPreference = "SilentlyContinue"

# Activate debug output if Verbose
if ($PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent) {
    $DebugPreference = 'Continue'
}

# Catch all unhadled errors and close Pssession to avoid this issue:
# Thanks for https://github.com/klmj for the idea
# http://www.checkyourlogs.net/?p=54583

trap{
    Disconnect-VBRServer -ErrorAction SilentlyContinue
    if($RemoteSession){Remove-PSSession -Session $RemoteSession}

    Write-Error $_.ToString()
    Write-Error $_.ScriptStackTrace

    Write-Output "<prtg>"
    Write-Output " <error>1</error>"
    Write-Output " <text>$($_.ToString())</text>"
    Write-Output "</prtg>"

    Exit
}

#region: Start Load VEEAM Snapin / Module (in local or remote session)

if ($PSRemote) {
    # Remoting on VBR server
    $RemoteSession = New-PSSession -Authentication Kerberos -ComputerName $BRHost
    if (-not $RemoteSession){throw "Cannot open remote session on '$BRHost' with user '$env:USERNAME'"}

    # Loading Module or PSSnapin then retrieve commands
    Invoke-Command -Session $RemoteSession -ScriptBlock {
        # Make sure PSModulePath includes Veeam Console
        $MyModulePath = "C:\Program Files\Veeam\Backup and Replication\Console\"
        $env:PSModulePath = $env:PSModulePath + "$([System.IO.Path]::PathSeparator)$MyModulePath"
        if ($Modules = Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
        try {
            $Modules | Import-Module -WarningAction SilentlyContinue
            }
            catch {
                throw "Failed to load Veeam Modules"
                }
        }
        else {
            Write-Host "No Veeam Modules found, Fallback to SnapIn."
            try {
                Add-PSSnapin -PassThru VeeamPSSnapIn -ErrorAction Stop | Out-Null
                }
                catch {
                    throw "Failed to load VeeamPSSnapIn and no Modules found"
                    }
        }
    } -ErrorAction Stop
    Import-PSSession -Session $RemoteSession -Module VeeamPSSnapin -ErrorAction Stop | Out-Null
} else {
    # Loading Module or PSSnapin
    # Make sure PSModulePath includes Veeam Console
    $MyModulePath = "C:\Program Files\Veeam\Backup and Replication\Console\"
    $env:PSModulePath = $env:PSModulePath + "$([System.IO.Path]::PathSeparator)$MyModulePath"
    if ($Modules = Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
        try {
            $Modules | Import-Module -WarningAction SilentlyContinue
            }
            catch {
                throw "Failed to load Veeam Modules"
                }
        }
        else {
            Write-Host "No Veeam Modules found, Fallback to SnapIn."
            try {
                Add-PSSnapin -PassThru VeeamPSSnapIn -ErrorAction Stop | Out-Null
                }
                catch {
                    throw "Failed to load VeeamPSSnapIn and no Modules found"
                    }
        }
}
#endregion

#region: Query Version
if ($Module = Get-Module -ListAvailable -Name Veeam.Backup.PowerShell) {
    try {
        switch ($Module.Version.ToString()) {
            {$_ -eq "1.0"} {  [int]$VbrVersion = "11"  }
            Default {[int]$VbrVersion = "11"}
        }
        }
        catch {
            throw "Failed to get Version from Module"
            }
    }
    else {
        Write-Host "No Veeam Modules found, Fallback to SnapIn."
        try {
            [int]$VbrVersion = (Get-PSSnapin VeeamPSSnapin).PSVersion.ToString()
            }
            catch {
                throw "Failed to get Version from Module or SnapIn"
                }
    }
#endregions

#region: Functions
<#
Big thanks to Shawn, creating an awsome Reporting Script:
http://blog.smasterson.com/2016/02/16/veeam-v9-my-veeam-report-v9-0-1/
#>

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
            $outputObj = New-RepoObject $r.Name $Hostname $r.FriendlyPath $r.GetContainer().CachedFreeSpace.InBytes $r.GetContainer().CachedTotalSpace.InBytes
        }
        $outputAry += $outputObj
    }
    End {
        $outputAry
    }
}
# Get-vPCRepoInfoPre11 curently not in use (Multi Version support Pending)
Function Get-vPCRepoInfoPre11 {
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
Write-Debug "Starting to Process Connection to '$BRHost' with user '$env:USERNAME' ..."
$OpenConnection = (Get-VBRServerSession).Server
if($OpenConnection -eq $BRHost) {
    Write-Debug "BRHost '$BRHost' is Already Connected..."
} elseif ($null -eq $OpenConnection) {
    Write-Debug "Connecting BRHost '$BRHost' with user '$env:USERNAME'..."
    try {
        Connect-VBRServer -Server $BRHost
    }
    catch {
        Throw "Failed to connect to Veeam BR Host '$BRHost' with user '$env:USERNAME'"
    }
} else {
    Write-Debug "Disconnection current BRHost..."
    Disconnect-VBRServer
    Write-Debug "Connecting new BRHost '$BRHost' with user '$env:USERNAME'..."

    try {
        Connect-VBRServer -Server $BRHost
    }
    catch {
        Throw "Failed to connect to Veeam BR Host '$BRHost' with user '$env:USERNAME'"
    }
}

$NewConnection = (Get-VBRServerSession).Server
if ($null -eq $NewConnection) {
    Throw "Failed to connect to Veeam BR Host '$BRHost' with user '$env:USERNAME'"
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
if ($VbrVersion -ge 11) {
    $RepoData = $repoList | Get-vPCRepoInfo
}
else {
    $RepoData = $repoList | Get-vPCRepoInfoPre11
}
$RepoReport = @()
ForEach ($RawRepo in $RepoData){
    If ($RawRepo.FreePercentage -lt $repoCritical) {$Status = "Critical"}
    ElseIf ($RawRepo.FreePercentage -lt $repoWarn) {$Status = "Warning"}
    ElseIf ($RawRepo.FreePercentage -eq "Unknown") {$Status = "Unknown"}
    Else {$Status = "OK"}
    $Object = "" | Select-Object "Repository Name", "Free (GB)", "Total (GB)", "Free (%)", "Status"
    $Object."Repository Name" = $RawRepo.Target
    $Object."Free (GB)" = $RawRepo.StorageFree
    $Object."Total (GB)" = $RawRepo.StorageTotal
    $Object."Free (%)" = $RawRepo.FreePercentage
    $Object."Status" = $Status

    $RepoReport += $Object
    }

<#
Thanks to Chris Arceneaux for his Cloud Repo Snippet
https://forums.veeam.com/powershell-f26/veeam-cloud-repository-disk-space-report-t63332.html
#>
if ($CloudRepos) {
    Write-Debug "Cloud Repo Section Entered..."
    $CloudProviders = Get-VBRCloudProvider

    foreach ($CloudProvider in $CloudProviders){
        if ($CloudProvider.Resources){
            foreach ($CloudProviderRessource in $CloudProvider.Resources){
                $CloudRepo = $CloudRepos | Where-Object {($_.CloudProvider.HostName -eq $CloudProvider.DNSName) -and ($_.Name -eq $CloudProviderRessource.RepositoryName)}
                $totalSpaceGb = [Math]::Round([Decimal]$CloudProviderRessource.RepositoryAllocatedSpace/1KB,2)
                #$totalUsedGb = [Math]::Round([Decimal]([Veeam.Backup.Core.CBackupRepository]::GetRepositoryBackupsSize($CloudRepo.Id.Guid))/1GB,2)
                if ($VbrVersion -ge 10) {
                    $totalUsedGb = [Math]::Round([Decimal]([Veeam.Backup.Core.CBackupRepository]::GetRepositoryBackupsSize($CloudRepo.Id.Guid))/1GB,2)
                }
                else {
                    $totalUsedGb = [Math]::Round([Decimal]([Veeam.Backup.Core.CBackupRepository]::GetRepositoryStoragesSize($CloudRepo.Id.Guid))/1GB,2)
                }
                $totalFreeGb = [Math]::Round($totalSpaceGb - $totalUsedGb,2)
                $freePercentage = [Math]::Round(($totalFreeGb/$totalSpaceGb)*100)
                If ($freePercentage -lt $repoCritical) {$Status = "Critical"}
                ElseIf ($freePercentage -lt $repoWarn) {$Status = "Warning"}
                ElseIf ($freePercentage -eq "Unknown") {$Status = "Unknown"}
                Else {$Status = "OK"}
                $Object = "" | Select-Object "Repository Name", "Free (GB)", "Total (GB)", "Free (%)", "Status"
                $Object."Repository Name" = $CloudProviderRessource.RepositoryName
                $Object."Free (GB)" = $totalFreeGb
                $Object."Total (GB)" = $totalSpaceGb
                $Object."Free (%)" = $freePercentage
                $Object."Status" = $Status

                $RepoReport += $Object
            }
        }
    }

}

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
