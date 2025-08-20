<#
.SYNOPSIS
Creates 3 IIS app pools and a website (with /app and /api apps) using a common identity.

Requires: IIS + WebAdministration module
Run as: Administrator
#>

Import-Module WebAdministration

# ========== VARIABLES ==========
$prefix         = "MyCompany"            # ← your "xxx" prefix (no spaces)
$domainSuffix   = "redrocksoftware.com"             # ← everything after xxxretail.
$appPoolUser    = "pas\rr${Prefix}" + "$"   # ← identity user

# Folders (customize if you like)
$rootPath = "C:\RedRock\Builds\${prefix}Retail"
$appPath  = Join-Path $rootPath "app"
$apiPath  = Join-Path $rootPath "api"

# Optional HTTPS binding (set to a cert thumbprint from LocalMachine\My to enable)
$httpsThumbprint = "e4fe84608ab2462d3b1493453abd786b61f6a42e"   # e.g. "‎a1b2c3d4e5f6..." (no spaces). Leave empty to skip HTTPS.

# ========== DERIVED NAMES ==========
$siteName     = "${prefix}Retail"
$poolRoot     = "${prefix}Retail"
$poolApp      = "${prefix}RetailAPP"
$poolApi      = "${prefix}RetailAPI"
$hostHeader   = ("{0}retail.{1}" -f $prefix, $domainSuffix).ToLowerInvariant()

# ========== HELPERS ==========
function New-Folder {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
        Write-Host "Created folder: $Path"
    } else {
        Write-Host "Folder exists: $Path"
    }
}

function New-Or-Update-AppPool {
    param([Parameter(Mandatory)][string]$Name)

    if (Test-Path "IIS:\AppPools\$Name") {
        Write-Host "App Pool '$Name' exists. Updating identity..."
    } else {
        New-WebAppPool -Name $Name | Out-Null
        Write-Host "Created App Pool: $Name"
    }

    # SpecificUser = 3
    Set-ItemProperty "IIS:\AppPools\$Name" -Name processModel.identityType -Value 3
    Set-ItemProperty "IIS:\AppPools\$Name" -Name processModel.userName   -Value $appPoolUser

    # Sensible defaults (optional)
    Set-ItemProperty "IIS:\AppPools\$Name" -Name startMode -Value "AlwaysRunning"
    Set-ItemProperty "IIS:\AppPools\$Name" -Name recycling.periodicRestart.time -Value ([TimeSpan]::FromHours(0)) # disable time-based restart
}

# ========== CREATE APP POOLS ==========
New-Or-Update-AppPool -Name $poolRoot
New-Or-Update-AppPool -Name $poolApp
New-Or-Update-AppPool -Name $poolApi

# ========== FOLDERS ==========
New-Folder $rootPath
New-Folder $appPath
New-Folder $apiPath

# ========== WEBSITE & BINDINGS ==========
# Create or update the site
if (Test-Path "IIS:\Sites\$siteName") {
    Write-Host "Site '$siteName' exists. Ensuring settings/bindings..."
    Set-ItemProperty "IIS:\Sites\$siteName" -Name applicationPool -Value $poolRoot
    Set-ItemProperty "IIS:\Sites\$siteName" -Name physicalPath    -Value $rootPath
} else {
    New-Website -Name $siteName -PhysicalPath $rootPath -Port 80 -HostHeader $hostHeader -ApplicationPool $poolRoot | Out-Null
    Write-Host "Created Website: $siteName bound to http://$hostHeader:80"
}

# Ensure HTTP binding exists
$httpBinding = Get-WebBinding -Name $siteName -Protocol "http" -ErrorAction SilentlyContinue |
               Where-Object { $_.bindingInformation -match ":80:$hostHeader" }
if (-not $httpBinding) {
    New-WebBinding -Name $siteName -Protocol "http" -Port 80 -HostHeader $hostHeader | Out-Null
    Write-Host "Added HTTP binding: :80:$hostHeader"
}

# Optional HTTPS binding
if ($httpsThumbprint -and $httpsThumbprint.Trim() -ne "") {
    $httpsBinding = Get-WebBinding -Name $siteName -Protocol "https" -ErrorAction SilentlyContinue |
                    Where-Object { $_.bindingInformation -match ":443:$hostHeader" }
    if (-not $httpsBinding) {
        New-WebBinding -Name $siteName -Protocol "https" -Port 443 -HostHeader $hostHeader | Out-Null
        # Link cert from LocalMachine\My with SNI (SSLFlags=1)
        New-Item "IIS:\SslBindings\0.0.0.0!443!$hostHeader" -Thumbprint $httpsThumbprint -SSLFlags 1 | Out-Null
        Write-Host "Added HTTPS binding: :443:$hostHeader with cert $httpsThumbprint"
    } else {
        Write-Host "HTTPS binding already present for $hostHeader"
    }
}

# ========== APPLICATIONS (/app and /api) ==========
function Set-WebApp {
    param(
        [Parameter(Mandatory)][string]$Site,
        [Parameter(Mandatory)][string]$Path,     # e.g. /app
        [Parameter(Mandatory)][string]$Physical,
        [Parameter(Mandatory)][string]$AppPool
    )

    $app = Get-WebApplication -Site $Site -Name $Path.TrimStart('/') -ErrorAction SilentlyContinue
    if ($app) {
        Set-ItemProperty "IIS:\Sites\$Site$Path" -Name applicationPool -Value $AppPool
        Set-ItemProperty "IIS:\Sites\$Site$Path" -Name physicalPath    -Value $Physical
        Write-Host "Updated application $Path → Pool '$AppPool', Path '$Physical'"
    } else {
        New-WebApplication -Site $Site -Name $Path.TrimStart('/') -PhysicalPath $Physical -ApplicationPool $AppPool | Out-Null
        Write-Host "Created application $Path → Pool '$AppPool', Path '$Physical'"
    }
}

Set-WebApp -Site $siteName -Path "/app" -Physical $appPath -AppPool $poolApp
Set-WebApp -Site $siteName -Path "/api" -Physical $apiPath -AppPool $poolApi


function Grant-FolderPermission {
    param (
        [string]$Path,
        [string]$User,
        [string]$Rights = "FullControl"
    )

    $acl = Get-Acl $Path
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($User, $Rights, "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $Path $acl
    Write-Host "Granted $Rights to $User on $Path"
}

$folders = @($rootPath, $appPath, $apiPath)
foreach ($f in $folders) {
    Grant-FolderPermission -Path $f -User $appPoolUser -Rights "FullControl"
}


Write-Host ""
Write-Host "Done! Visit: https://$hostHeader/app"
Write-Host "Site: $siteName"
Write-Host "Pools: $poolRoot, $poolApp, $poolApi"
