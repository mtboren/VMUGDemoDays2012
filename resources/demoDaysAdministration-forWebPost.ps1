
<#
CNAME for View CS: vdi.vmug.local
View CS:	vmug-vdi01, vmug-vdi02
vCenter:  	vmug-vc01
SQL server:	vmug-sql01
AD DCs:		vmug-dc01, vmug-dc02
ESXi hosts:
	172.20.20.23
	172.20.20.31
	172.20.20.32
	172.20.20.33
	172.20.20.34
	172.20.20.35
	172.20.20.36
	172.20.20.37
	172.20.20.38
#>


## get the vC admin creds
$credVCAdmin = Get-Credential administrator

Connect-VIServer vmug-vc01 -Credential $credVCAdmin


## to start SSH on VMHosts
Get-VMHost | Get-VMHostService | ?{$_.Key -eq "TSM-SSH"} | ?{$_.Running -eq $false} | Start-VMHostService -Confirm:$false
## to stop SSH on VMHosts
Get-VMHost | Get-VMHostService | ?{$_.Key -eq "TSM-SSH"} | ?{$_.Running -eq $true} | Stop-VMHostService -Confirm:$false


## get creds for ESXi hosts
$credESXiRoot = Get-Credential root

## arr of all VMHosts names
$arrVMHostNames = Get-VMHost | %{$_.Name}

## cmd to add the given line to the config file on VMHosts
$strCmdToRun = "echo 'vhv.allow = ```"TRUE```"' >> /etc/vmware/config"
## cmd to echo out the config file
#$strCmdToRun = "cat /etc/vmware/config"
$arrVMHostNames | %{plink.exe -l root -pw <rootPasswd> $_ $strCmdToRun}



## added add'l portgroup to the std vSwitch0
Get-Cluster | Get-VMHost | Get-VirtualSwitch -Name vSwitch0 | %{New-VirtualPortGroup -VirtualSwitch $_ -Name PowerCLI-32 -VLanId 132 -Confirm:$false}
Get-Cluster | Get-VMHost | Get-VirtualSwitch -Name vSwitch0 | %{New-VirtualPortGroup -VirtualSwitch $_ -Name SRM-32 -VLanId 232 -Confirm:$false}


###############
## clone vApps
## name of cluster in which to make vApps
$strVDIAndMgmtClustername = "VDI and Management"
## prefix name of the vApp
#$strVAppNamePrefix = "SRM"
$strVAppNamePrefix = "PowerCLI"
## the name of the source vApp to clone
$strSourceVAppName = "base_PowerCLI_done"
#$strSourceVAppName = "base_SRM-00_CLONE"

## clone the vApp
21..25 | %{
    $strNewVAppName = "$strVAppNamePrefix-{0:d2}" -f $_
    #$dstToUse = Get-Datastore vapp-vmfs* | sort FreeSpaceMB -Descending:$true | select -First 1
    $dstToUse = Get-Datastore vapp-vmfs* | Get-Random
    New-VApp -Name $strNewVAppName -Location (Get-Cluster $strVDIAndMgmtClustername | Get-VMHost | Get-Random) -Datastore $dstToUse -VApp $strSourceVAppName -RunAsync
} ## end foreach-object

## when clones are done, can move the vApps to the given folder
$strFolderToWhichToMoveVApp = "${strVAppNamePrefix}_vApps"    ## vApp inventory folder is PowerCLI_vApps or SRM_vApps
$oDestFolder = Get-Folder $strFolderToWhichToMoveVApp
Get-VApp "$strVAppNamePrefix*" | ?{$_.ExtensionData.ParentFolder.ToString() -ne $oDestFolder.Id} | Move-VApp -Destination $oDestFolder

## set proper NetworkName for NIC on VMs in the vApps (portgroup names match the vApp names); -NetworkName param is cASeSensitIVe!
21..25 | %{
    $intLabNumber = $_
    $strVAppName = "$strVAppNamePrefix-{0:d2}" -f $intLabNumber
    Get-VApp $strVAppName | Get-VM | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName $strVAppName -Confirm:$false 
} ## end foreach-object

## end clone vApps
###############



###############
## prep vApps
## take snapshots of vApp VMs -- do in PoweredOn or PoweredOff state?
#$strVAppNamePrefix = "SRM"
$strVAppNamePrefix = "PowerCLI"
21..25 | %{
    ## make vApp name
    $strNewVAppName = "$strVAppNamePrefix-{0:d2}" -f $_
    Get-VApp $strNewVAppName | Get-VM | New-Snapshot -Name "0" -Description "Initial state" -Memory -Quiesce -Confirm:$false -RunAsync
} ## end foreach-object

21..25 | %{$strNewVAppName = "$strVAppNamePrefix-{0:d2}" -f $_; Get-VApp $strNewVAppName | Start-VApp -Confirm:$false -RunAsync}
## for the PowerCLI stuff -- restart the ESXi VMs so that vC shows them as powered on
#21..25 | %{$strNewVAppName = "$strVAppNamePrefix-{0:d2}" -f $_; Get-VApp $strNewVAppName | Get-VM esxi* | Restart-VM -Confirm:$false}
21..22 | %{
    ## make vApp name
    $strNewVAppName = "$strVAppNamePrefix-{0:d2}" -f $_
    Get-VApp $strNewVAppName | Get-VM | New-Snapshot -Name "1" -Description "Powered on" -Memory -Quiesce -Confirm:$false -RunAsync
} ## end foreach-object
## end prep vApps
###############


$strVDIVMsBaseName = "PowerCLI"
21..25 | %{Get-VM $("vm-${strVDIVMsBaseName}-{0:d2}" -f $_)} | %{
#Get-VM "vm-${strVDIVMsBaseName}-*" | %{
    $strVMName = $_.Name
    Get-NetworkAdapter -VM $_ -Name "Network Adapter 2" | Set-NetworkAdapter -NetworkName $strVMName.Trim("vm-") -Confirm:$false -WhatIf
} ## end foreach-Object
#-- CHECK ON POWERCLI-06, SRM-03, SRM07 -- not sure 2nd nic is on right virtual network


###############
## reset vApp for next user -- revert all VMs in the vApp to snapshot
$strVAppToReset = "PowerCLI-03"
$strSnapshotName = "1"

$vappToReset = Get-VApp $strVAppToReset
## stop VMs in vApp
#$vappToReset | Get-VM | Stop-VM -Confirm:$false
$vappToReset | Get-VM | Set-VM -Snapshot $strSnapshotName -Confirm:$false

## start the vApp if reverting to snapshot 0 (if snapshot 1, the VMs were on)
#$vappToReset | Start-VApp -Confirm:$false
Get-VM "vm-$strVAppToReset" | Restart-VMGuest -Confirm:$false
## end reset vApp -- revert all VMs in the vApp to snapshot
###############


## reporting stuff
## show snapshots for each vApp
11..20 | %{Get-VApp powercli-$_} | %{$strVAppName = $_.Name; Get-VM -Location $_ | Get-Snapshot | Select @{n="vapp";e={$strVAppName}},Name,VM}
