Collection of Advanced PRTG Sensors
===================================
[![Build status](https://ci.appveyor.com/api/projects/status/u6d6wrj8y07k7twq/branch/master?svg=true)](https://ci.appveyor.com/project/mycloudrevolution/advanced-prtg-sensors/branch/master)

# About

## Project Owner:

Markus Kraus [@vMarkus_K](https://twitter.com/vMarkus_K)

MY CLOUD-(R)EVOLUTION [mycloudrevolution.com](http://mycloudrevolution.com/)

## Project WebSite

[PRTG Blog Category](http://mycloudrevolution.com/category/prtg/)

## Project Details

This is a Collection of my Advanced [PRTG](https://www.de.paessler.com/prtg/) Sensors.
Most Advanced PRTG Sensors were created during posts on my private blog, but everyone is welcome contribute.

## Project Contribution

Every issue, enhancement request and pull request is welcome!

If you open a pull request please note:
+ Do not change Channel Naming (Script update should be non distruptive)
+ Do not change default behavior if Features are added (Script update should be non distruptive)
+ Do not remove existing Debug Output
+ Add Debug Output for new Sensor Features
+ Run Pester Test
## Advanced PRTG Sensor Products

+ Veeam Backup & Replication
+ Veeam Cloud Connect
+ VMware vCenter
+ Microsoft Windows

# Contribute

Contact me via any channel or create a pull request.

# Project Folder Structure

## Veeam

Veeam realted Sensors.

+ Veeam Backup & Replication - [Blog Post](http://mycloudrevolution.com/2016/03/21/veeam-prtg-sensor-reloaded/)

    For the latest features please use the Script: `PRTG-VeeamBRStats-v3.ps1`
    - PSx64.exe is not required any more
    - [PRTG HTTP Push Sensor](https://www.paessler.com/manuals/prtg/http_push_data_advanced_sensor) can be used (less load on PRTG Probe / more secure from VBR perspective)

    The `PRTG-VeeamBRStats.ps1` is marked as "legacy" and no further updates will happen to this version.


![PRTG-VeeamBRStats](/media/PRTG-VeeamBRStats.png)

+ Veeam Cloud Connect - [Blog Post](http://mycloudrevolution.com/2016/08/16/prtg-veeam-cloud-connect-monitoring/)

## Windows

Microsoft Windows realted Sensors.

+ Scheduled Task - [Blog Post](http://mycloudrevolution.com/2016/09/15/prtg-advanced-scheduled-task-sensor/)