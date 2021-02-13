## create empty VMs
## guestID enums:  http://pubs.vmware.com/vsphere-50/index.jsp?topic=%2Fcom.vmware.wssdk.apiref.doc_50%2Fvim.vm.GuestOsDescriptor.GuestOsIdentifier.html&path=5_0_2_7_15_2
## new VM from scratch
New-VM -Version v7 -Location ClientMachines -Name Win7x32_empty -VMHost (Get-VMHost | Get-Random) -DiskMB 4KB -MemoryMB 2KB -DiskStorageFormat Thin -GuestId windows7Guest -NumCpu 1 
New-VM -Version v8 -Location OtherMachines -Name Win2012Tmpl -VMHost esxi02 -DiskMB 10KB -MemoryMB 2KB -DiskStorageFormat Thin -GuestId windows8Server64Guest -NumCpu 2




$strMacToFind = "00:50:56:83:00:69"

## find VM by MAC addr
$strMacToFind = "00:0c:29:e0:a5:4c"
## return the .NET View object(s) for the VM(s) with the NIC w/ the given MAC
Get-View -Viewtype VirtualMachine -Property Name, Config.Hardware.Device | `
	?{$_.Config.Hardware.Device | ?{($_ -is [VMware.Vim.VirtualEthernetCard]) `
		-and ($_.MacAddress -eq $strMacToFind)}}

## or, just some summary info about the VM:  VM name and MAC address(es)
Get-View -Viewtype VirtualMachine -Property Name, Config.Hardware.Device | ?{$_.Config.Hardware.Device | `
	?{($_ -is [VMware.Vim.VirtualEthernetCard]) -and ($_.MacAddress -eq $strMacToFind)}} | `
	Select name, @{n="MAC(s)"; e={($_.Config.Hardware.Device | ?{($_ -is [VMware.Vim.VirtualEthernetCard])} | %{$_.MacAddress}) -join ","}}

## for Matt:  getting VM's MACs
Get-View -Viewtype VirtualMachine -Property Name, Config.Hardware.Device | Select name, @{n="MAC(s)"; e={($_.Config.Hardware.Device | ?{($_ -is [VMware.Vim.VirtualEthernetCard])} | %{$_.MacAddress}) -join ","}}








another to discuss might be:
Get-VMHostHBAWWN.ps1



## code to set MTU on all virtual switches and port groups except for the Management Network in a Cluster
#Author: JHilger

## set cluster upon which to act, and the MTU size to set
$strClusterName="LAB"; $intTargetMTU = 9000

## get current MTU info for virtual switches and host network adapters (vmnics)
$arrVMHosts = Get-Cluster $strClusterName | Get-VMHost
$arrVMHosts | Get-VirtualSwitch | Select VMHost,name,Mtu
$arrVMHosts | Get-VMHostNetworkAdapter | Select VMHost,name,Mtu

Get-Cluster $strClusterName | Get-VMHost | %{
	## get the virtual switches and change MTU
	Get-VirtualSwitch -VMHost $_ | Where-Object {$_.Mtu -ne $intTargetMTU} | Set-VirtualSwitch -Mtu $intTargetMTU -Confirm:$false -WhatIf
	## get host virtual network adapters that have a portgroup and change MTU size (if not already set to desired value)
	Get-VMHostNetworkAdapter -VMHost $_ | Where-Object {$_.PortGroupName -and ($_.Mtu -ne $intTargetMTU)} | Set-VMHostNetworkAdapter -Mtu $intTargetMTU -Confirm:$false -WhatIf
} ## end foreach-object






chg host passwds:
$strDCToChange = "SomeDC"

## the current (old) root password
$strOldRootPassword = "old_password"

## the new root password
$strNewRootPassword = "new_password"

## Create "error report" array
$arrHostsWithErrors = @()

## Get all VMHosts in chosen datacenter and then connect directly to them and change the root password, then disconnect from the host
#Get-Datacenter -Name $strDCToChange | Get-VMHost | Sort-Object -Property Name | ForEach-Object {
Get-VMHost | Sort-Object -Property Name | ForEach-Object {
	Connect-VIServer -Server $_.Name -User root -Password $strOldRootPassword
	$objVMHostAccount = $null
	$objVMHostAccount = Set-VMHostAccount -Server $_.Name -UserAccount (Get-VMHostAccount -Server $_.Name -User root) -Password $strNewRootPassword
	if (($objVMHostAccount -eq $null) -or ($objVMHostAccount.GetType().Name -ne "HostUserAccountImpl")) {$arrHostsWithErrors += $_.Name}
	Disconnect-VIServer -Server $_.Name -Confirm:$false
}







## current root password, to be changed
$strOldRootPassword = "vmware#1"
## new root password to set
$strNewRootPassword = "vmware#2"

## Create "error report" array
$arrHostsWithErrors = @()

Get-VMHost | ForEach-Object {
	$oConnectionTmp = Connect-VIServer -Server $_.Name -User root -Password $strOldRootPassword
	$objVMHostAccount = $null
	$objVMHostAccount = Set-VMHostAccount -Server $_.Name -UserAccount (Get-VMHostAccount -Server $_.Name -User root) -Password $strNewRootPassword
	if (($objVMHostAccount -eq $null) -or ($objVMHostAccount.GetType().Name -ne "HostUserAccountImpl")) {$arrHostsWithErrors += $_.Name}
	Disconnect-VIServer -Server $_.Name -Confirm:$false
} ## end foreach-object



## Script function: find duplicate MAC addresses, and list the VMs/addresses involved
## Author: vNugglets.com

## create a collection of custom PSObjects with VM/MACAddress info
$colDevMacAddrInfo = `
Get-View -ViewType VirtualMachine -Property Name,Config.Hardware.Device -Filter @{"Config.Template" = "False"} | %{
   $strVMName = $_.Name
   $_.Config.Hardware.Device | Where-Object {$_ -is [VMware.Vim.VirtualEthernetCard]} | %{
       New-Object -Type PSObject -Property @{VMName = $strVMName; MacAddr = $_.MacAddress}
   } ## end foreach-object
} ## end foreach-object

## check if all of the MAC addresses are unique? (returns true/false)
($colDevMacAddrInfo | Select-Object -unique MacAddr).Count -eq $colDevMacAddrInfo.Count

## get the non-unique MAC addresses, returning objects with the count of the duplicates, the duplicate MAC, and the VM names that have the duplicate MAC
$colDevMacAddrInfo | Group-Object MacAddr | Where-Object {$_.count -gt 1} | Select-Object Count,@{n="DuplicateMAC"; e={$_.Name}},@{n="VMNames"; e={($_.Group | %{$_.VMName}) -join ","}}






## code to set MAC addr as duplicate
$strNewMACAddr = "00:50:56:00:51:a6"
Get-VM web-srv-01 | Get-NetworkAdapter -Name "Network Adapter 2" | Set-NetworkAdapter -MacAddress $strNewMACAddr -Confirm:$false
Get-VM centos0 | Get-NetworkAdapter -Name "Network Adapter 1" | Set-NetworkAdapter -MacAddress $strNewMACAddr -Confirm:$false






<#	.Description
Code to get SCSI LUN info for the extent(s) of a given datastore.  Helpful for, say, wanting to get a device name for a datastores so as to be able to check its performance info in resxtop, for example.  Matt Boren, Jan 2012
#>
## name pattern to filter on for datastores
#$strDStoreNamePattern = $datastoreNamePattern_str
$strDStoreNamePattern = "esxi01-local"

&{Get-View -ViewType Datastore -Property Name, Info -Filter @{"Name" = $strDStoreNamePattern} | %{
	New-Object -Type PSObject -Property @{
		DStoreName = $_.Name
		DiskDeviceNames = ($_.Info.Vmfs.Extent | %{$_.DiskName}) -join ","
	} ## end new-object
} ## end foreach-object
} | select DStoreName,DiskDeviceNames




##get datastore by extent canonical name
param(
## canonical name of ScsiLun on which datastore is made
[string]$CanonicalExtentName_str = "naa.3333333333333333333333333333333333"
) ## end param

#$strCanonicalExtentName = $CanonicalExtentName_str
$strCanonicalExtentName = "mpx.vmhba1:C0:T0:L0"
$viewMatchingDStore = Get-View -ViewType Datastore -Property Name,Info | ?{$_.Info.Vmfs.Extent | ?{$_.DiskName -eq $strCanonicalExtentName}}
if ($viewMatchingDStore) {
	New-Object -Type PSObject -Property @{
		DatastoreName = $viewMatchingDStore.Name
		CapacityGB = [Math]::Round(($viewMatchingDStore.Info.Vmfs.Capacity / 1GB), 0)
		BlockSizeMB = $viewMatchingDStore.Info.Vmfs.BlockSizeMB
		MatchingExtent = $strCanonicalExtentName
		NumExtents = @($viewMatchingDStore.Info.Vmfs.Extent).Count
	} | select DatastoreName, CapacityGB, BlockSizeMB, MatchingExtent, NumExtents
} ## end if
else {$false}