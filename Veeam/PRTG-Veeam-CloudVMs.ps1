<#
	.SYNOPSIS
	PRTG Veeam Cloud Connect Usage Sensor
  
	.DESCRIPTION
	Advanced Sensor will Report Cloud Connect Tenant Statistics
        
	.EXAMPLE
	PRTG-Veeam-CloudVMs.ps1 -Server VeeamEM.lan.local -HTTPS:$True -Port 9398 -Authentication <dummy>

	.EXAMPLE
	PRTG-Veeam-CloudVMs.ps1 -Server VeeamEM.lan.local -HTTPS:$False -Port 9399 -Authentication <dummy>
	
	.Notes
	NAME:  PRTG-Veeam-CloudVMs.ps1
	LASTEDIT: 08/11/2016
	VERSION: 1.5
	KEYWORDS: Veeam, Cloud Connect, PRTG
   
	.Link
	http://mycloudrevolution.com/
 
 #Requires PS -Version 3.0  
 #>
[cmdletbinding()]
param(
    [Parameter(Position=0, Mandatory=$false)]
    	[String] $Server = "veeam01.lan.local",
	[Parameter(Position=1, Mandatory=$false)]
		[Boolean] $HTTPS = $True,
	[Parameter(Position=2, Mandatory=$false)]
		[String] $Port = "9398",
	[Parameter(Position=3, Mandatory=$false)]
		[String] $Authentication = "<dummy>"

)

#region: Workaround for SelfSigned Cert
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
#endregion

#region: Switch Http/s
if ($HTTPS -eq $True) {$Proto = "https"} else {$Proto = "http"}
#endregion

#region: POST - Authorization
[String] $URL = $Proto + "://" + $Server + ":" + $Port + "/api/sessionMngr/?v=v1_2"
Write-Verbose "Authorization Url: $URL"
$Auth = @{uri = $URL;
                   Method = 'POST';
                   Headers = @{Authorization = 'Basic ' + $Authentication;
           }
   }
try {$AuthXML = Invoke-WebRequest @Auth -ErrorAction Stop} catch {Write-Error "`nERROR: Authorization Failed!";Exit 1}
#endregion

#region: GET - Session Statistics
[String] $URL = $Proto + "://" + $Server + ":" + $Port + "/api/cloud/tenants"
Write-Verbose "Session Statistics Url: $URL"
$Tenants = @{uri = $URL;
                   Method = 'GET';
				   Headers = @{'X-RestSvcSessionId' = $AuthXML.Headers['X-RestSvcSessionId'];
           } 
	}
try {$TenantsXML = Invoke-RestMethod @Tenants -ErrorAction Stop} catch {Write-Error "`nERROR: Get Session Statistics Failed!";Exit 1}
#endregion

#region: Get Tenant Details
[Array] $Hrefs	= $TenantsXML.EntityReferences.Ref.Href
$VCCBillings	= @()

for ( $i = 0; $i -lt $Hrefs.Count; $i++){
	[String] $URL = $Hrefs[$i] + "?format=Entity"
	Write-Verbose "Tenant Detail Url: $URL"
	$TenantsDetails = @{uri = $URL;
    	               Method = 'GET';
					   Headers = @{'X-RestSvcSessionId' = $AuthXML.Headers['X-RestSvcSessionId'];
           	} 
		}
	try {$TenantsDetailsXML = Invoke-RestMethod @TenantsDetails -ErrorAction Stop} catch {Write-Error "`nERROR: Get Tenant Details Failed!";Exit 1}
#endregion

#region: Build Report	
# Customer Name
[String] $CustomerName = $TenantsDetailsXML.CloudTenant.Name
# Customer BaaS and DRaaS Objects
[Int] $BackupCount = $TenantsDetailsXML.CloudTenant.BackupCount
[Int] $ReplicaCount = $TenantsDetailsXML.CloudTenant.ReplicaCount
# Customer BaaS Quotas
[Array] $BackupUsedQuota = $TenantsDetailsXML.CloudTenant.Resources.CloudTenantResource.RepositoryQuota.UsedQuota
[Int] $BackupUsedQuota = (($BackupUsedQuota) | Measure-Object -Sum).Sum
[Array] $BackupQuota = $TenantsDetailsXML.CloudTenant.Resources.CloudTenantResource.RepositoryQuota.Quota
[Int] $BackupQuota = (($BackupQuota) | Measure-Object -Sum).Sum
# Customer DRaaS Quotas
[Array]  $ReplicaMemoryUsageMb = $TenantsDetailsXML.CloudTenant.ComputeResources.CloudTenantComputeResource.ComputeResourceStats.MemoryUsageMb
if ($ReplicaMemoryUsageMb -eq $null) {$ReplicaMemoryUsageMb = 0}
[Int] $ReplicaMemoryUsageMb = (($ReplicaMemoryUsageMb) | Measure-Object -Sum).Sum
[Array]  $ReplicaCPUCount = $TenantsDetailsXML.CloudTenant.ComputeResources.CloudTenantComputeResource.ComputeResourceStats.CPUCount
if ($ReplicaCPUCount -eq $null) {$ReplicaCPUCount = 0}
[Int] $ReplicaCPUCount = (($ReplicaCPUCount) | Measure-Object -Sum).Sum
[Array]  $ReplicaStorageUsageGb = $TenantsDetailsXML.CloudTenant.ComputeResources.CloudTenantComputeResource.ComputeResourceStats.StorageResourceStats.StorageResourceStat.StorageUsageGb
if ($ReplicaStorageUsageGb -eq $null) {$ReplicaStorageUsageGb = 0}
[Int] $ReplicaStorageUsageGb = (($ReplicaStorageUsageGb) | Measure-Object -Sum).Sum
[Array]  $ReplicaStorageLimitGb = $TenantsDetailsXML.CloudTenant.ComputeResources.CloudTenantComputeResource.ComputeResourceStats.StorageResourceStats.StorageResourceStat.StorageLimitGb
if ($ReplicaStorageLimitGb -eq $null) {$ReplicaStorageLimitGb = 0; $ReplicaStorageUsedPerc = 0}
[Int] $ReplicaStorageLimitGb = (($ReplicaStorageLimitGb) | Measure-Object -Sum).Sum

if ($ReplicaStorageLimitGb -gt 0) {
	$ReplicaStorageUsedPerc =  [Math]::Round(($ReplicaStorageUsageGb / $ReplicaStorageLimitGb) * 100,0)	
	}

$VCCObject = [PSCustomObject] @{
	CustomerName  = $CustomerName
	BackupCount = $BackupCount
	ReplicaCount = $ReplicaCount
	BackupQuotaGb = $BackupQuota
	BackupUsedQuotaGb = $BackupUsedQuota
	BackupQuotaUsedPerc = [Math]::Round(($BackupUsedQuota / $BackupQuota) * 100,0)
	ReplicaMemoryUsageMb = $ReplicaMemoryUsageMb
	ReplicaCPUCount = $ReplicaCPUCount
	ReplicaStorageLimitGb = $ReplicaStorageLimitGb
	ReplicaStorageUsageGb = $ReplicaStorageUsageGb
	ReplicaStorageUsedPerc = $ReplicaStorageUsedPerc
}
$VCCBillings += $VCCObject
}
#endregion

#region: XML Output for PRTG
Write-Host "<prtg>" 
foreach ($VCCBilling in $VCCBillings){
	$BackupCount_Name = "BackupCount - " + $VCCBilling.CustomerName
	$BackupCount_Value = $VCCBilling.BackupCount

	Write-Host "<result>"
    	        "<channel>$BackupCount_Name</channel>"
        	    "<value>$BackupCount_Value</value>"
            	"<showChart>1</showChart>"
               	"<showTable>1</showTable>"
               	"</result>" 
				
	$ReplicaCount_Name = "ReplicaCount - " + $VCCBilling.CustomerName
	$ReplicaCount_Value = $VCCBilling.ReplicaCount

	Write-Host "<result>"
    	        "<channel>$ReplicaCount_Name</channel>"
        	    "<value>$ReplicaCount_Value</value>"
            	"<showChart>1</showChart>"
               	"<showTable>1</showTable>"
               	"</result>" 

	$BackupQuotaGb_Name = "BackupQuotaGb - " + $VCCBilling.CustomerName
	$BackupQuotaGb_Value = $VCCBilling.BackupQuotaGb

	Write-Host "<result>"
    	        "<channel>$BackupQuotaGb_Name</channel>"
        	    "<value>$BackupQuotaGb_Value</value>"
				"<unit>Custom</unit>"
				"<customUnit>GB</customUnit>"
            	"<showChart>1</showChart>"
               	"<showTable>1</showTable>"
               	"</result>" 


	$BackupUsedQuotaGb_Name = "BackupUsedQuotaGb - " + $VCCBilling.CustomerName
	$BackupUsedQuotaGb_Value = $VCCBilling.BackupUsedQuotaGb

	Write-Host "<result>"
    	        "<channel>$BackupUsedQuotaGb_Name</channel>"
        	    "<value>$BackupUsedQuotaGb_Value</value>"
				"<unit>Custom</unit>"
				"<customUnit>GB</customUnit>"
            	"<showChart>1</showChart>"
               	"<showTable>1</showTable>"
               	"</result>" 

	$BackupQuotaUsed_Name = "BackupQuotaUsed - " + $VCCBilling.CustomerName
	$BackupQuotaUsed_Value = $VCCBilling.BackupQuotaUsedPerc

	Write-Host "<result>"
    	        "<channel>$BackupQuotaUsed_Name</channel>"
        	    "<value>$BackupQuotaUsed_Value</value>"
				"<unit>Percent</unit>"
				"<mode>Absolute</mode>"
            	"<showChart>1</showChart>"
               	"<showTable>1</showTable>"
                "<LimitMaxWarning>80</LimitMaxWarning>"
                "<LimitMaxError>90</LimitMaxError>"
                "<LimitMode>1</LimitMode>"
               	"</result>"

	$ReplicaMemoryUsageMb_Name = "ReplicaMemoryUsageMb  - " + $VCCBilling.CustomerName
	$ReplicaMemoryUsageMb_Value = $VCCBilling.ReplicaMemoryUsageMb 

	Write-Host "<result>"
    	        "<channel>$ReplicaMemoryUsageMb_Name</channel>"
        	    "<value>$ReplicaMemoryUsageMb_Value</value>"
				"<unit>Custom</unit>"
				"<customUnit>MB</customUnit>"
            	"<showChart>1</showChart>"
               	"<showTable>1</showTable>"
               	"</result>" 
				
	$ReplicaCPUCount_Name = "ReplicaCPUCount - " + $VCCBilling.CustomerName
	$ReplicaCPUCount_Value = $VCCBilling.ReplicaCPUCount

	Write-Host "<result>"
    	        "<channel>$ReplicaCPUCount_Name</channel>"
        	    "<value>$ReplicaCPUCount_Value</value>"
            	"<showChart>1</showChart>"
               	"<showTable>1</showTable>"
               	"</result>"
				
	$ReplicaStorageLimitGb_Name = "ReplicaStorageLimitGb  - " + $VCCBilling.CustomerName
	$ReplicaStorageLimitGb_Value = $VCCBilling.ReplicaStorageLimitGb
	Write-Host "<result>"
    	        "<channel>$ReplicaStorageLimitGb_Name</channel>"
        	    "<value>$ReplicaStorageLimitGb_Value</value>"
				"<unit>Custom</unit>"
				"<customUnit>GB</customUnit>"
            	"<showChart>1</showChart>"
               	"<showTable>1</showTable>"
               	"</result>" 
				
	$ReplicaStorageUsageGb_Name = "ReplicaStorageUsageGb  - " + $VCCBilling.CustomerName
	$ReplicaStorageUsageGb_Value = $VCCBilling.ReplicaStorageUsageGb 

	Write-Host "<result>"
    	        "<channel>$ReplicaStorageUsageGb_Name</channel>"
        	    "<value>$ReplicaStorageUsageGb_Value</value>"
				"<unit>Custom</unit>"
				"<customUnit>GB</customUnit>"
            	"<showChart>1</showChart>"
               	"<showTable>1</showTable>"
               	"</result>" 

	$ReplicaStorageUsed_Name = "ReplicaStorageUsed - " + $VCCBilling.CustomerName
	$ReplicaStorageUsed_Value = $VCCBilling.ReplicaStorageUsedPerc

	Write-Host "<result>"
				"<channel>$ReplicaStorageUsed_Name</channel>"
				"<value>$ReplicaStorageUsed_Value</value>"
				"<unit>Percent</unit>"
				"<mode>Absolute</mode>"
				"<showChart>1</showChart>"
				"<showTable>1</showTable>"
				"<LimitMaxWarning>80</LimitMaxWarning>"
				"<LimitMaxError>90</LimitMaxError>"
				"<LimitMode>1</LimitMode>"
				"</result>"
	}

$BackupCount_Total = (($VCCBillings) | Measure-Object 'BackupCount' -Sum).Sum
Write-Host "<result>"
               "<channel>BackupCount - Total</channel>"
               "<value>$BackupCount_Total</value>"
               "<showChart>1</showChart>"
               "<showTable>1</showTable>"
            "</result>"

$ReplicaCount_Total = (($VCCBillings) | Measure-Object 'ReplicaCount' -Sum).Sum
Write-Host "<result>"
               "<channel>ReplicaCount - Total</channel>"
               "<value>$ReplicaCount_Total</value>"
               "<showChart>1</showChart>"
               "<showTable>1</showTable>"
            "</result>" 
			
Write-Host "</prtg>" 
#endregion

#region: Debug
if ($DebugPreference -eq "Inquire") {
	$VCCBillings | ft * -Autosize
}
#endregion