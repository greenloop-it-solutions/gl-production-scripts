sc.exe config "MMS" obj="Localsystem"
net stop MMS && net start MMS
net user svc_Acronis /delete
