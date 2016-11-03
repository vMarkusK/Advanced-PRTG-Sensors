<a name="Title">
# Title

HPE StoreOnce PowerShell Module

|Navigation|
|-----------------|
|[About](#About)|
|[Contribute](#Contribute)|
|[Features](#Features)|
|[Enhancements](#Enhancements)|


<a name="About">
# About
[*Back to top*](#Title)

Project Owner: Markus Kraus

Project WebSite: http://mycloudrevolution.com/projekte/storeonce-powershell-module/

Project Details:

This module leverages the HPE StoreOnce REST API with PowerShell.
This first cmdlets will be for reporting purposes and after that some basic administrative cmdlets should be added.

+ Create Stores
+ Change Permissions
+ Delete Stores
+ etc.

<a name="Contribute">
# Contribute
[*Back to top*](#Title)

* Request access to the project Slack Channel (https://mycloudrevolution.slack.com/messages/storeonce-ps/)

Request form: http://mycloudrevolution.com/projekte/storeonce-powershell-module/
Or contact me via any other channel...

<a name="Features">
# Features
[*Back to top*](#Title)

## Set-SOCredentials

Creates a Base64 hash for further requests against your StoreOnce system(s).
This should be the first Commandlet you use from this module.

![Set-SOCredentials](/Media/Set-SOCredentials_Neu.png)

## Get-SOSIDs

Lists all ServiceSets from your StoreOnce system(s).

Outputs: ArrayIP,SSID,Name,Alias,OverallHealth,SerialNumber,Capacity(GB).Free(GB),UserData(GB),DiskData(GB)

![Get-SOSIDs](/Media/Get-SOSIDs_Neu.png)

## Get-SOCatStores

Lists all Catalyst Stores from your StoreOnce system(s).

Outputs: ArrayIP,SSID,Name,ID,Status,Health,SizeOnDisk(GB),UserDataStored(GB),DedupeRatio

![Get-SOCatStores](/Media/Get-SOCatStores_Neu.png)

## Get-SONasShares

Lists all NAS Stores from your StoreOnce system(s).

Outputs: ArrayIP,SSID,Name,ID,AccessProtocol,SizeOnDisk(GB),UserDataStored(GB),DedupeRatio

![Get-SONasShares](/Media/Get-SONasShares_Neu.png)

## Get-SOCatClients

Lists all Catalyst Clients from your StoreOnce system(s).

Outputs: ArrayIP,SSID,Name,ID,Description,canCreateStores,canSetServerProperties,canManageClientPermissions

![Get-SOCatClients](/Media/Get-SOCatClients_Neu.png)

## Get-SOCatStoreAccess

Lists Clients with Access Permissions of a Catalyst Store.

Outputs: Client,allowAccess

![Get-SOCatStoreAccess](/Media/Get-SOCatStoreAccess_Neu.png)

## New-SOCatStore

Creates a single StoreOnce Catalyst store with default options on a given Service Set on your StoreOnce system.

![New-SOCatStore](/Media/New-SOCatStore_Neu.png)

## New-SOCatClient

Creates a StoreOnce Catalyst Client on all Service Sets on your StoreOnce system.

![New-SOCatClient](/Media/New-SOCatClient_Neu.png)

## Set-SOCatStoreAccess

Permit or deny Client access to a StoreOnce Catalyst Store.

![Set-SOCatStoreAccess](/Media/Set-SOCatStoreAccess_Neu.png)

<a name="Enhancements">
# Enhancements
[*Back to top*](#Title)

Version 1.1
+ New: IP Connection Test before REST Calls

Version 1.0
+ Enhanced: Module restructuring. Each Function has now its own psm1

Version 0.9
+ New: Permit or deny Client access to a StoreOnce Catalyst Store
+ Fix: Parameter Positions

Version 0.8
+ New: Creates a StoreOnce Catalyst client

Version 0.7
+ New: Creates a StoreOnce Catalyst store
+ Enhanced: More details for Get-SOCatStores

Version 0.6
+ Enhanced: Parameter Position declaration 
+ Enhanced: Output Reorganization

Version 0.5.2
+ Enhanced: New Cert Handling 
+ Enhanced: Cmdlet Set-SOCredentials rewritten

Version 0.5.1
+ Enhanced: Optional Credential verification for Set-SOCredentials Commandlet

Version 0.5
+ New: Get Clients (Users) with Access Permissions of a Catalyst Store

Version 0.4.1
+ Enhanced: Added ID not NAS and Catalyst

Version 0.4
+ New: Get StoreOnce Catalyst Clients (User)

Version 0.3
+ New: Get StoreOnce NAS Shares
+ Renamed StoreOnce Catalyst Stores Commandlet
+ Enhanced: Added Synopsis to Functions

Version 0.2.1
+ Fixed: Issue #4 - Secure Password Input

Version 0.2
+ New: Get StoreOnce Catalyst Stores

Version 0.1
+ New: Credential Handling for REST Calls
+ New: Get StoreOnce SIDs

