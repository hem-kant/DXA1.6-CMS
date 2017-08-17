<#
.SYNOPSIS
   Enables the CID service for the DXA .NET Web Application on 2013sp1
.EXAMPLE
   .\cid-install.ps1 -distDestination "C:\inetpub\wwwroot\DXA_Staging" -Verbose
#>

[CmdletBinding( SupportsShouldProcess=$true, PositionalBinding=$false)]
Param(
    #File system path of the root folder of DXA Website.
    [Parameter(Mandatory=$true, HelpMessage="File system path of the root folder of DXA Website")]
    [string]$distDestination,
   
    #Path on which to handle any CID requests (defaults to /cid/*).
    [Parameter(Mandatory=$false, HelpMessage="Specify path for handling CID requests")]
    [string]$cidPath = "/cid/*"   
)

function GetOrCreate-Node([string]$path)
{
    $node = $config.SelectSingleNode($path)
    if(!$node)
    {
        $parts = $path.Split("/", [System.StringSplitOptions]::RemoveEmptyEntries)
        $path = ""        
        $parent = $config
        foreach($part in $parts)
        {
            $path += "/$part"
            $node = $config.SelectSingleNode($path)
            if(!$node)
            {
                $node = $config.CreateElement($part)
                $parent.AppendChild($node) | Out-Null
            }
            $parent = $node
        }        
    }
    return $node
}

function Set-Attribute([string]$path, [string]$attributeName, [string]$attributeValue)
{   
    $node = GetOrCreate-Node($path)
    $node.SetAttribute($attributeName, $attributeValue)    
}

function Set-UnityTypeMapping([string]$type, [string]$mappingValue)
{
    Write-Host "Adding unity type mapping for $type to $mappingValue"
    $node = $config.SelectSingleNode("/unity/containers/container/types/type[@type='$type']")
    if (!$node) 
    {
        $mapping = GetOrCreate-Node("/unity/containers/container/types")
        $node = $config.CreateElement("type")
        $node.SetAttribute("type", $type) 
        $child = $config.CreateElement("lifetime");
        $child.SetAttribute("type", "singleton");       
        $node.AppendChild($child) | Out-Null
        $mapping.AppendChild($node) | Out-Null   
    }
    $node.SetAttribute("mapTo", $mappingValue)
}

function Add-HttpHandler([string]$name, [string]$verb, [string]$path, [string]$type)
{
    Write-Host "Adding http handler: $name"
    $httpHandlersNode = GetOrCreate-Node("/configuration/system.webServer/handlers") #$config.SelectSingleNode("/configuration/system.webServer/handlers")
    $httpHandlerNode = $httpHandlersNode.SelectSingleNode("add[@name='$name']")
    if (!$httpHandlerNode) 
    {      
        $httpHandlerNode = $config.CreateElement("add")
        $httpHandlerNode.SetAttribute("name", "$name")        
        $httpHandlersNode.AppendChild($httpHandlerNode) | Out-Null
    }
    $httpHandlerNode.SetAttribute("verb", $verb)
    $httpHandlerNode.SetAttribute("path", $path)
    $httpHandlerNode.SetAttribute("type", $type)
}

# Update Unity.config
$unityConfigFile = "$distDestination\Unity.config"
Write-Host ("Updating '$unityConfigFile' ...")
[xml]$config = Get-Content $unityConfigFile -ErrorAction Stop
Set-UnityTypeMapping "IMediaHelper" "ContextualMediaHelper"
$config.Save("$unityConfigFile")

# Update Web,config
$webConfigFile = "$distDestination\Web.config"
Write-Host "Updating '$webConfigFile' ..."
[xml]$config = Get-Content $webConfigFile -ErrorAction Stop

# Add the CID httpHandler that will respond to requests
Add-HttpHandler "ImageTransformerHandler" "*" "$cidPath" "Tridion.Context.Image.Handler.ImageTransformerHandler"

# We need this at the moment so CID requests can be passed a port number
Set-Attribute "/configuration/system.web/httpRuntime" "requestPathInvalidCharacters" "<,>,*,%,&,?"

# Save Web.config
$config.Save("$webConfigFile")

# Copy web application files
Write-Host "Copying web application files..."
$distSource = Split-Path $MyInvocation.MyCommand.Path
Copy-Item $distSource\web-ref-cid\* $distDestination\bin -Recurse -Force

Write-Host "Done."
