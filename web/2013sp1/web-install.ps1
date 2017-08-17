<#
.SYNOPSIS
   Deploys the DXA .NET Web Application on SDL Tridion 2013 SP1
.EXAMPLE
   .\web-install.ps1 -distDestination "C:\inetpub\wwwroot\DXA_Staging" -webName "DXA Staging" -sitePublicationId 1 -Verbose -Confirm
#>

[CmdletBinding( SupportsShouldProcess=$true, PositionalBinding=$false)]
Param(
    [Parameter(Mandatory=$true, HelpMessage="Type of DXA web application to deploy: 'Staging' or 'Live'")]
    [ValidateSet("Staging", "Live")]
    [string]$deployType,

    [Parameter(Mandatory=$true, HelpMessage="File system path of the root folder of DXA Website")]
    [string]$distDestination,

    [Parameter(Mandatory=$false, HelpMessage="Name of the DXA Website")]
    [string]$webName = "DXA",

    [Parameter(Mandatory=$false, HelpMessage="Host header of DXA Website used in configs. Specify empty string to use current computer name.")]
    [string]$siteDomain = "",

    [Parameter(Mandatory=$true, HelpMessage="Port for DXA Website")]
    [int]$sitePort,

    [Parameter(Mandatory=$false, HelpMessage="Path to the log directory")]
    [string]$logFolder = "C:\temp\logs",

    #The logging level (ERROR,WARN,INFO,DEBUG,TRACE in order of increasing verbosity) for the DXA log file and CD logs. Defaults to INFO.
    [Parameter(Mandatory=$false, HelpMessage="The logging level (ERROR,WARN,INFO,DEBUG,TRACE in order of increasing verbosity) for the DXA log file and CD logs. Defaults to INFO.")]
    [ValidateSet( "ERROR", "WARN", "INFO", "DEBUG", "TRACE")]
    [string]$logLevel = "INFO",

    [Parameter(Mandatory=$false, HelpMessage="Log file path")]
    [string]$siteLogFile = "site.log",

    [Parameter(Mandatory=$true, HelpMessage="CM Publication ID (integer) of the DXA Website Publication")]
    [int]$sitePublicationId,

    [Parameter(Mandatory=$false, HelpMessage="Database Server name for CD Session Preview database")]
    [string]$sessionDbServer,

    # Can be either 'MSSQL' or 'ORACLESQL'. Another possible value 'database2' is deprecated.
    [Parameter(Mandatory=$false, HelpMessage="Database Server type for CD Session Preview database: 'MSSQL' (default) or 'ORACLESQL'")]
    [ValidateSet("MSSQL", "ORACLESQL", "DB2")]
    [string]$sessionDbType,

    [Parameter(Mandatory=$false, HelpMessage="Database Server port for CD Session Preview database")]
    [int]$sessionDbPort,

    [Parameter(Mandatory=$false, HelpMessage="Name of CD Session Preview database")]
    [string]$sessionDbName,

    [Parameter(Mandatory=$false, HelpMessage="User name for CD Session Preview database")]
    [string]$sessionDbUser,

    [Parameter(Mandatory=$false, HelpMessage="Password for CD Session Preview database")]
    [string]$sessionDbPassword,

    [Parameter(Mandatory=$true, HelpMessage="Database Server name for CD database")]
    [string]$defaultDbServer,

    # Can be either 'MSSQL' or 'ORACLESQL'. Another possible value 'database2' is deprecated.
    [Parameter(Mandatory=$false, HelpMessage="database Server type for CD database: 'MSSQL' (default) or 'ORACLESQL'")]
    [ValidateSet("MSSQL", "ORACLESQL", "DB2")]
    [string]$defaultDbType = "MSSQL",

    [Parameter(Mandatory=$false, HelpMessage="Database Server port for CD database")]
    [int]$defaultDbPort,

    [Parameter(Mandatory=$true, HelpMessage="Name of CD database")]
    [string]$defaultDbName,

    [Parameter(Mandatory=$true, HelpMessage="User name for CD database")]
    [string]$defaultDbUser,

    [Parameter(Mandatory=$true, HelpMessage="Password for CD database")]
    [string]$defaultDbPassword,

    [Parameter(Mandatory=$false, HelpMessage="Switch that indicates non-interactive mode")]
    [Switch]$NonInteractive,

    [Parameter(Mandatory=$false, HelpMessage="Action to perform when DXA Website already exists: 'Recreate', 'Preserve' or 'Cancel' (default)")]
    [ValidateSet("Recreate", "Preserve", "Cancel")]
    [string]$webSiteAction = "Cancel",

    #Exclude Core Module from installation
    [Parameter(Mandatory=$false, HelpMessage="Exclude Core Module from installation")]
    [switch]$noCoreModule = $false,

    #The type of Navigation Provider to use. Can be 'Static' or 'Dynamic'.
    [Parameter(Mandatory=$false, HelpMessage="The type of Navigation Provider to use. Can be 'Static' or 'Dynamic'")]
    [ValidateSet("Static", "Dynamic")]
    [string]$navigationProvider = "Static"
)

if ($deployType -eq "Staging") 
{
    #Derive Session DB info from Default DB info (if not explicitly specified)
    if (!$sessionDbServer) { $sessionDbServer = $defaultDbServer }
    if (!$sessionDbPort) { $sessionDbPort = $defaultDbPort }
    if (!$sessionDbType) { $sessionDbType = $defaultDbType }
    if (!$sessionDbName) { $sessionDbName = $defaultDbName + "_session" }
    if (!$sessionDbUser) { $sessionDbUser = $defaultDbUser }
    if (!$sessionDbPassword) { $sessionDbPassword = $defaultDbPassword }

    #Write-Output "sessionDbPort: $sessionDbPort"
}

#Terminate script on first occurred exception
$ErrorActionPreference = "Stop"

#Process 'WhatIf' and 'Confirm' options
if (!($pscmdlet.ShouldProcess("System", "Deploy web application"))) { return }

#Initialization
$IsInteractiveMode = !((gwmi -Class Win32_Process -Filter "ProcessID=$PID").commandline -match "-NonInteractive") -and !$NonInteractive

$distSource = Split-Path $MyInvocation.MyCommand.Path

$DomainName = (Get-WmiObject -Class Win32_ComputerSystem).Domain
$FullComputerName = $env:computername
if (![string]::IsNullOrEmpty($DomainName))
{
    $FullComputerName = $FullComputerName + "." + $DomainName
}

if (!$siteDomain) {
    $siteDomain = $FullComputerName
    $siteHeader = ""
} else {
    $siteHeader = $siteDomain
}

$defaultDbPorts = @{"MSSQL"=1433;"ORACLESQL"=1521;"DB2"=50000}
if (!$sessionDbPort) { $sessionDbPort = $defaultDbPorts[$sessionDbType] }
if (!$defaultDbPort) { $defaultDbPort = $defaultDbPorts[$defaultDbType] }

#Format data
$distSource = $distSource.TrimEnd("\")
$distDestination = $distDestination.TrimEnd("\")
$logFolder = $logFolder.Replace("\", "/")
$siteLogFile = Join-Path $logFolder $siteLogFile
$siteDomain = $siteDomain.ToLower()

#Set web site
Write-Output "Setting web site and web application..."
Import-Module "WebAdministration"
$webSite = Get-Item IIS:\Sites\$webName -ErrorAction SilentlyContinue
if ($webSite) {
    $recreate = New-Object System.Management.Automation.Host.ChoiceDescription "&Recreate", "Delete old web site and create new with specified parameters."
    $preserve = New-Object System.Management.Automation.Host.ChoiceDescription "&Preserve", "Use existing web site for web application deployment."
    $cancel = New-Object System.Management.Automation.Host.ChoiceDescription "&Cancel", "Cancel setup."
    $RecreatePreserveCancelOptions = [System.Management.Automation.Host.ChoiceDescription[]]($recreate, $preserve, $cancel)
    $choice = 1
    if ($IsInteractiveMode) {
        $choice = $host.UI.PromptForChoice("Warning", "Web Site '$webName' already exists. Select 'Recreate' to overwrite website. Select 'Preserve' to use existing website. Select 'Cancel' to cancel setup.", $RecreatePreserveCancelOptions, 1)
    } else {
        $actionChoices = @{"Recreate"=0;"Preserve"=1;"Cancel"=2}
        $choice = $actionChoices[$webSiteAction]
    }
    if ($choice -eq 2) {
        Write-Output "Setup was canceled because Web Site '$webName' already exists."
        return
    }
    if ($choice -eq 0) {
        Write-Output "Recreating website..."
        $appPool = Get-Item IIS:\AppPools\$webName -ErrorAction SilentlyContinue
        if($appPool) { 
            $appPool.Stop()
            while (-not ($appPool.state -eq "Stopped")) { Start-Sleep -Milliseconds 100 }
        }
        Remove-Item IIS:\Sites\$webName -Recurse
        if (Test-Path $distDestination) {
            Remove-Item $distDestination -Recurse -Force
        }
        New-Item IIS:\Sites\$webName -Bindings @{protocol="http";bindingInformation=":"+$sitePort+":"+$siteHeader} -PhysicalPath $distDestination
    }
    if ($choice -eq 1) {
        Write-Output "Using existing website..."
        $sitePort = $webSite.bindings.Collection[0].bindingInformation.Split(":")[1]
        $siteHeader = $webSite.bindings.Collection[0].bindingInformation.Split(":")[2]
        $distDestination = $webSite.physicalPath.TrimEnd("\")
    }
    if ($siteHeader) {
        $siteDomain = $siteHeader.ToLower()
    }
} else {
    New-Item IIS:\Sites\$webName -Bindings @{protocol="http";bindingInformation=":"+$sitePort+":"+$siteHeader} -PhysicalPath $distDestination
}

#Copy web application files
Write-Output "Copying web application files..."
if (!(Test-Path $distDestination)) {
    New-Item -ItemType Directory -Path $distDestination | Out-Null
}
Copy-Item $distSource\dist\* $distDestination -Recurse

#Set Application Pool
Write-Output "Setting application pool..."
$appPool = Get-Item IIS:\AppPools\$webName -ErrorAction SilentlyContinue
if(!$appPool) {
    $appPool = New-Item IIS:\AppPools\$webName
}
$appPool.managedRuntimeVersion = "v4.0" #v2.0
$appPool.managedPipelineMode = 0 #0 - Integrated, 1 - Classic
$appPool.processModel.loadUserProfile = $true
$appPool.processModel.identityType = "NetworkService"
$appPool | Set-Item
Set-ItemProperty IIS:\Sites\$webName -Name applicationPool -value $webName
$appPool.Start()

#Copy Tridion assemblies and configuration
Write-Output "Copying Tridion assemblies and configuration..."
$fileSets = @("$distSource\web-ref\**\*", "$distSource\web-ref\*")
if ($deployType -eq "Staging") {
    $fileSets = @("$distSource\web-ref-staging\**\*", "$distSource\web-ref-staging\*") + $fileSets
}
Get-Item $fileSets | Foreach {
        $destFile = Join-Path $distDestination\bin $_.FullName.Substring($_.FullName.IndexOf("\", $distSource.Length + 1) + 1)        
        Write-Verbose "Source file: $($_.FullName)"
        Write-Verbose "Dest file: $($destFile)"
        if (!(Test-Path $destFile)){
            #Create subfolder if it doesn't exist
			if (!(Test-Path (Split-Path $destFile))){
				New-Item -ItemType Directory -Path (Split-Path $destFile) | Out-Null
			}			
            Write-Output ("Copying missing file: " + $destFile)
            Copy-Item $_ $destFile -Recurse
        }
    }

#Set folder permissions
Write-Output "Setting rights " $distDestination, "NetworkService", "FullControl", "..."
$Acl = Get-Acl $distDestination
$permission = "NetworkService" ,"FullControl","ContainerInherit,ObjectInherit","None","Allow"
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission    
$Acl.SetAccessRule($accessRule)
Set-Acl $distDestination $Acl

#Update configs
Write-Output "Updating configs..."

##logback.xml
[xml]$config = Get-Content $distDestination\bin\config\logback.xml -ErrorAction Stop
($config.configuration.property | ?{$_.name -eq "log.folder"}).SetAttribute("value", $logFolder)
($config.configuration.property | ?{$_.name -eq "log.level"}).SetAttribute("value", $logLevel)
$config.Save("$distDestination\bin\config\logback.xml")
Write-Output "Updated 'logback.xml' file with data: log.folder value=$logFolder."

##cd_dynamic_conf.xml
[xml]$config = Get-Content $distDestination\bin\config\cd_dynamic_conf.xml -ErrorAction Stop
$publicationNode = $config.Configuration.URLMappings.StaticMappings.Publications.Publication
$publicationNode.SetAttribute("Id", $sitePublicationId)
$publicationNode.Host.SetAttribute("Domain", $siteDomain)
$publicationNode.Host.SetAttribute("Port", $sitePort)
$config.Save("$distDestination\bin\config\cd_dynamic_conf.xml")
Write-Output "Updated 'cd_dynamic_conf.xml' file with data: Publication Id=$sitePublicationId; Domain = $siteDomain; Port = $sitePort."

##cd_link_conf.xml
[xml]$config = Get-Content $distDestination\bin\config\cd_link_conf.xml -ErrorAction Stop
$publicationNode = $config.Configuration.Publications.Publication
$publicationNode.SetAttribute("Id", $sitePublicationId)
$publicationNode.Host.SetAttribute("Domain", $siteDomain)
$publicationNode.Host.SetAttribute("Port", $sitePort)
$config.Save("$distDestination\bin\config\cd_link_conf.xml")
Write-Output "Updated 'cd_link_conf.xml' file with data: Publication Id=$sitePublicationId; Domain = $siteDomain; Port = $sitePort."

##cd_storage_conf.xml
function Set-StorageSettings ($configPath, $id, [ValidateSet("MSSQL", "ORACLESQL", "DB2")]$dbType, $dbServerName, $dbServerPort, $dbName, $dbUserName, $dbUserPassword) {
    Write-Verbose "Settings storage configuration with data: configPath=$configPath; id=$id; dbType=$dbType; dbServerName=$dbServerName; dbServerPort=$dbServerPort; dbName=$dbName; dbUserName=$dbUserName; dbUserPasswor=$dbUserPasswor"
    [xml]$config = Get-Content $configPath
    $storageNode = $config.SelectSingleNode("//Storage[@Id='$($id)']")
    $storageNode.SetAttribute("dialect", $dbType)
    $dataSourceNode = $storageNode.DataSource
    $dataSourceNode.SelectNodes("Property") | %{ $dataSourceNode.RemoveChild($_) } | Out-Null
    if ($dbType -eq "MSSQL") {
        $dataSourceNode.SetAttribute("Class", "com.microsoft.sqlserver.jdbc.SQLServerDataSource")
        $propertyNodeListInfo = @(
            @{Name="serverName";Value=$dbServerName},
            @{Name="portNumber";Value="$dbServerPort"},
            @{Name="databaseName";Value="$dbName"},
            @{Name="user";Value="$dbUserName"},
            @{Name="password";Value="$dbUserPassword"}
        )
    }
    if ($dbType -eq "ORACLESQL") {
        $dataSourceNode.SetAttribute("Class", "oracle.jdbc.pool.OracleDataSource")
        $propertyNodeListInfo = @(
            @{Name="driverType";Value="thin"},
            @{Name="networkProtocol";Value="tcp"},
            @{Name="serverName";Value=$dbServerName},
            @{Name="portNumber";Value="$dbServerPort"},
            @{Name="databaseName";Value="$dbName"},
            @{Name="user";Value="$dbUserName"},
            @{Name="password";Value="$dbUserPassword"}
        )
    }
    if ($dbType -eq "DB2") {
        $dataSourceNode.SetAttribute("Class", "com.ibm.db2.jcc.DB2SimpleDataSource")
        $propertyNodeListInfo = @(
            @{Name="serverName";Value=$dbServerName},
            @{Name="portNumber";Value="$dbServerPort"},
            @{Name="databaseName";Value="$dbName"},
            @{Name="user";Value="$dbUserName"},
            @{Name="password";Value="$dbUserPassword"}
            @{Name="driverType";Value="4"}
        )
    }
    $propertyNodeListInfo | %{
                                Write-Verbose "Adding 'Property' node with name='$($_.Name)' and value='$($_.Value)'"
                                $newPropertyNode = $config.CreateElement("Property")
                                $newPropertyNode.SetAttribute("Name", $_.Name)
                                $newPropertyNode.SetAttribute("Value", $_.Value)
                                $dataSourceNode.AppendChild($newPropertyNode) | Out-Null            
                            }

    $config.Save($configPath)
    Write-Verbose "Saved changes to config file"
}

$configPath = Join-Path $distDestination "bin\config\cd_storage_conf.xml"

if ($deployType -eq "Staging") { Set-StorageSettings $configPath "sessionDb" $sessionDbType $sessionDbServer $sessionDbPort $sessionDbName $sessionDbUser $sessionDbPassword }
Set-StorageSettings $configPath "defaultdb" $defaultDbType $defaultDbServer $defaultDbPort $defaultDbName $defaultDbUser $defaultDbPassword
Write-Output ("Updated 'cd_storage_conf.xml' file with data:")
if ($deployType -eq "Staging") { Write-Output ("- Session preview database: dbType=$sessionDbType; serverName=$sessionDbServer; portNumber=$sessionDbPort; databaseName=$sessionDbName; user=$sessionDbUser; password=****") }
Write-Output ("- Staging/live database: dbType=$defaultDbType; serverName=$defaultDbServer; portNumber=$defaultDbPort; databaseName=$defaultDbName; user=$defaultDbUser; password=****")

# Update Log.config
$logConfigFile = "$distDestination\Log.config"
Write-Host ("Updating '$logConfigFile' ...")
[xml]$logConfig = Get-Content $logConfigFile -ErrorAction Stop
$appenderNode = $logConfig.log4net.appender | ?{$_.name -eq "RollingFile"}
if ($appenderNode) 
{ 
    $appenderNode.file.SetAttribute("value", $siteLogFile)
    Write-Host "Set log file location to '$siteLogFile'" 
}
$logLevelNode = $logConfig.log4net.root.level
if ($logLevelNode)
{
    $logLevelNode.value = $logLevel
    Write-Host "Set log level '$logLevel'"
}
$logConfig.Save($logConfigFile)

##Unity.config
function SetImplementationType([string]$interfaceType, [string]$implementationType, [xml]$config)
{
    $typeElement = $config.SelectSingleNode("/unity/containers/container/types/type[@type='$interfaceType']")
    $typeElement.SetAttribute("mapTo", "$implementationType")
}

[xml]$config = Get-Content $distDestination\Unity.config -ErrorAction Stop
SetImplementationType "ILocalizationResolver" "CdConfigLocalizationResolver" $config
SetImplementationType "IContextClaimsProvider" "AdfContextClaimsProvider" $config
$config.Save("$distDestination\Unity.config")
Write-Output "Updated 'Unity.config'."

##Web.config
function Set-AppSetting([string]$key, [string]$value)
{
    $appSettingsNode = $config.configuration.appSettings

    $appSettingNode = $appSettingsNode.SelectSingleNode("add[@key='$key']")
    if (!$appSettingNode) {
        $appSettingNode = $config.CreateElement("add")
        $appSettingNode.SetAttribute("key", "$key")
        $dummy = $appSettingsNode.AppendChild($appSettingNode)
    }
    $appSettingNode.SetAttribute("value", $value)
}

$webConfigFile = "$distDestination\Web.config"
Write-Host "Updating '$webConfigFile' ..."
[xml]$config = Get-Content $webConfigFile -ErrorAction Stop

Write-Host "Deploy type: '$deployType'"
if ($deployType -eq "Staging")
{
    Set-AppSetting "DD4T.CacheSettings.Default" 5
}
else
{
    Set-AppSetting "DD4T.CacheSettings.Default" 300
}
$config.Save("$webConfigFile")

#Update Unity.config
function Set-UnityTypeMapping([string] $type, [string] $mapTo, [xml] $configDoc) 
{
	$mainContainer = $configDoc.unity.containers.container | ? {$_.name -eq "main"}
	if (!$mainContainer) 
	{
        throw "Main container not found."
    }

	$typeElement = $mainContainer.types.type | ? {$_.type -eq $type}
	if ($typeElement)
    {
        Write-Host "Found existing type mapping: '$type' -> '$mapTo'"
    }
    else
	{
		$typeElement = $configDoc.CreateElement("type")
		$mainContainer.types.AppendChild($typeElement) | Out-Null
	}

	$typeElement.SetAttribute("type",$type)
	$typeElement.SetAttribute("mapTo",$mapTo)

    Write-Host "Set type mapping: '$type' -> '$mapTo'"
}

if ($navigationProvider -ne "Static")
{
    $unityConfigFile = "$distDestination\Unity.config"
    Write-Host "Updating '$unityConfigFile' ..."
    [xml]$unityConfigDoc = Get-Content $unityConfigFile -ErrorAction Stop
    Set-UnityTypeMapping "INavigationProvider" "$($navigationProvider)NavigationProvider" $unityConfigDoc
    $unityConfigDoc.Save($unityConfigFile)
}

if(!$noCoreModule)
{
    . (Join-Path $distSource "\..\..\modules\Core\web-install.ps1") -distDestination $distDestination
}

Write-Host "Done."