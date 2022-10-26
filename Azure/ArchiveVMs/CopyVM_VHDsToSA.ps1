# this script gets all VHDs for VMs in the specified resource group, and copies them into a designated storage account.
# The storage account needs to already exist.
# SM 10/26/2022

Connect-AzAccount -UseDeviceAuthentication

$RG = "Source VM Resource Group Name--all VHDs for these VMs will be copied.:"
$StorageAccount = Read-Host "Storage Account Name (destination):"
$RgSA = Read-Host "Resource Group of that storage account:"

#initialize a var to hold the copy job information so we can check it to monitor completion
$BlobCopyJobs = @() 

#$vm = (get-azVM)[0]
#$vm = (get-azVM)[1]
#$vm = (get-azVM)[2]
$Vms = get-azVM
foreach ($vm in $VMs) {
	#Region Copy the OS disk
	$Vm = Get-Azvm  -name $($vm.name) -resourcegroup $RG
	# To Get the list of your managed disks
	$Disk = Get-AzDisk -ResourceGroupName $RG -DiskName $($VM.StorageProfile.OsDisk.Name)
	# To Grant access to the disk for Export(SAS URL)
	$sas = Grant-AzDiskAccess -ResourceGroupName $Disk.ResourceGroupName -DiskName $Disk.Name -DurationInSecond 604800 -Access Read
	$Storageaccesskey = $null
	$StorageAccessKey =  Get-AzStorageAccountKey -ResourceGroupName $RgSA -Name $StorageAccount
	# Get storage account context
	$destContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $StorageAccessKey.Value[0]
	$DiskName = $Disk.Name
	New-AzStorageContainer -Name $($vm.name).ToLower() -Context $destContext
	# Start copy
	$copyOSBlob = start-AzStorageBlobCopy -AbsoluteUri $sas.AccessSAS -DestContainer $($vm.name).ToLower() -DestContext $destContext -DestBlob "$DiskName.vhd"
	#endRegion
	 
	#Region Copy Data Disks
	$Vm = Get-Azvm  -name $($vm.name) -resourcegroup $RG
	$DataDisks = $($VM.StorageProfile.DataDisks)
	foreach ($DataDisk in $DataDisks) {
		$DataDiskName = $DataDisk.Name
		write-host $DataDiskName
		$Disk = Get-AzDisk -ResourceGroupName $RG -DiskName $DataDiskName
		# To Grant access to the disk for Export(SAS URL)
		$sas = Grant-AzDiskAccess -ResourceGroupName $Disk.ResourceGroupName -DiskName $Disk.Name -DurationInSecond 108000 -Access Read
		$Storageaccesskey = $null
		$StorageAccessKey =  Get-AzStorageAccountKey -ResourceGroupName $RgSA -Name $StorageAccount
		# Get storage account context
		$destContext = New-AzStorageContext -StorageAccountName $StorageAccount -StorageAccountKey $StorageAccessKey.Value[0]
		$DiskName = $Disk.Name
		# Start copy
		$copyBlob = Start-AzStorageBlobCopy -AbsoluteUri $sas.AccessSAS -DestContainer $($vm.name).ToLower() -DestContext $destContext -DestBlob "$DiskName.vhd"   
	}
	$BlobCopyJobs += $copyOSBlob
	$BlobCopyJobs += $copyBlob
}

#display Status of copy jobs. repeat this as necessary.
$BlobCopyJobs | Get-AzStorageBlobCopyState | Select-Object Status,@{Name='percentComplete';Expression={100*($_.BytesCopied / $_.TotalBytes)}}
