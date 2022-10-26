# use blobporter to convert page blops to block blobs. Necessary for archiving. Files will be placed into a new container with the same name as the old one and '-archive' appended.
# if you get errors, increase the blob size '-b' parameter.
$StorageAccount = Read-Host "Storage Account Name:"
$RgSA = Read-Host "Resource Group Name:"
$Container = Read-Host "Provide the container for the blob you want to convert"
$StorageAccessKey =  Get-AzStorageAccountKey -ResourceGroupName $RgSA -Name $StorageAccount
$env:ACCOUNT_NAME= $StorageAccount
$env:ACCOUNT_KEY= $StorageAccessKey.Value[0]
$env:SRC_ACCOUNT_KEY = $StorageAccessKey.Value[0]
./blobporter -f "https://$($StorageAccount).blob.core.windows.net/$($Container)/" -c "$($Container)-archive" -t blob-blockblob -b 128MB
