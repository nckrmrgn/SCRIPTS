# Define variables
$folderPath = "C:\YourWebsiteFolder"  # Update with your desired folder path
$websiteName = "YourWebsite"           # Update with your desired website name
$appPoolName = "YourAppPool"           # Update with your desired app pool name
$appPoolUser = "YourAppPoolUser"       # Update with the username for the app pool identity
$certificateThumbprint = "959dcb43ae4a3c82271cd76f455401d2432905d0"  # Update with the thumbprint of your SSL certificate

# Create a folder for the website
New-Item -Path $folderPath -ItemType Directory

# Add the app pool user to the folder's security settings
$acl = Get-Acl -Path $folderPath
$identityReference = New-Object System.Security.Principal.NTAccount($appPoolUser)
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($identityReference, "FullControl", "Allow")
$acl.SetAccessRule($accessRule)
Set-Acl -Path $folderPath -AclObject $acl

# Create an IIS application pool
New-WebAppPool -Name $appPoolName

# Set the user for the application pool identity
Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name "ProcessModel.IdentityType" -Value "SpecificUser"
Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name "ProcessModel.UserName" -Value $appPoolUser
Set-ItemProperty "IIS:\AppPools\$appPoolName" -Name "ProcessModel.Password" -Value (Read-Host -AsSecureString)

# Create an IIS website and associate it with the folder and app pool
New-Website -Name $websiteName -PhysicalPath $folderPath -ApplicationPool $appPoolName -Port 80

# Add a binding for port 443 and specify the SSL certificate
New-WebBinding -Name $websiteName -Port 443 -Protocol "https"
Set-WebBinding -Name $websiteName -BindingInformation "*:443:" -PropertyName "CertificateHash" -Value $certificateThumbprint

# Start the IIS website
Start-Website -Name $websiteName
