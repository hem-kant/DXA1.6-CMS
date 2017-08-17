<#
.SYNOPSIS
    Prepares SDL Web 8 Topology Manager for DXA CMS import.
.DESCRIPTION
    This script ensures that the CD Topology Types which are used by DXA Business Process Types are configured in Topology Manager.
    It also ensures that CD Topologies, CD Environments, Websites and Web Applications are configured and associated with the DXA Site Type.
    For that purpose, it may prompt for configuration values; it is non possible to run the script in non-interactive mode. 
    The script must be run before running the DXA cms-import.ps1 scripts.
.EXAMPLE
   .\ttm-prepare.ps1
#>


$dxaSiteTypeKey = "DxaSiteType"
$dxaExampleSiteKey = "DxaExampleSite"
$cdTopologyTypes = Get-TtmCdTopologyType
$cdTopologies = Get-TtmCdTopology
$cdEnvironments = Get-TtmCdEnvironment
$websites = Get-TtmWebsite


function Get-CdTopologyType($id, $name, $environmentPurposes) 
{
    $cdTopologyType = $cdTopologyTypes | Where { $_.Id -eq $id }
    if ($cdTopologyType) 
    {
        if (@(Compare-Object $cdTopologyType.EnvironmentPurposes $environmentPurposes -SyncWindow 0).Length -ne 0) 
        {
            throw "CD Topology Type with ID '$id' already exists, but with different EnvironmentPurposes: " + ($cdTopologyType.EnvironmentPurposes -join ",")
        }    
    }
    else
    {
        $cdTopologyType = Add-TtmCdTopologyType -Id $id -Name $name -EnvironmentPurposes $environmentPurposes
        Write-Host "CD Topology Type registered with Id '$id' and Name '$name'."
    }
    return $cdTopologyType
}


function Get-CdTopology($id, $name, $description, $cdTopologyTypeId, $cdEnvironmentIds)
{
    $cdTopology = $cdTopologies | Where { $_.Id -eq $id }
    if (!$cdTopology)
    {
        $cdTopology = Add-TtmCdTopology -Id $id -Name $name -Description $description -CdTopologyTypeId $cdTopologyTypeId -CdEnvironmentIds $cdEnvironmentIds
        Write-Host "CD Topology registered with Id '$id' and Name '$name'."
    }
    return $cdTopology
}


function Get-CdEnvironment($purpose)
{
    $cdEnvironment = $cdEnvironments | Where { $_.EnvironmentPurpose -eq $purpose }
    if (!$cdEnvironment)
    {
        Write-Host "Please provide information for the '$purpose' CD Environment:"
        do
        {
            $discoveryServiceUrl = Read-Host "`tEnter Discovery Service URL (leave empty if you don't want to configure it)"
            if (!$discoveryServiceUrl) { return $null }

            $oauthClientId = Read-Host "`tEnter OAuth Client ID (leave empty if OAuth is not used)"
            if ($oauthClientId)
            {
                $oauthClientSecret = Read-Host "`tEnter OAuth Client Secret"
                $cdEnvironment = Add-TtmCdEnvironment `
                    -EnvironmentPurpose $purpose `
                    -DiscoveryEndpointUrl $discoveryServiceUrl `
                    -AuthenticationType OAuth `
                    -ClientId $oauthClientId `
                    -ClientSecret $oauthClientSecret `
                    -ErrorVariable cmdletError
            }
            else
            {
                $cdEnvironment = Add-TtmCdEnvironment `
                    -EnvironmentPurpose $purpose `
                    -DiscoveryEndpointUrl $discoveryServiceUrl `
                    -ErrorVariable cmdletError
            }
        }
        until (!$cmdletError)
        Write-Host "CD Environment registered with Id '$($cdEnvironment.Id)' and Purpose '$purpose'."
    }
    elseif ($cdEnvironment.Length -gt 1)
    {
        $cdEnvironment = $cdEnvironment[0]
        Write-Host "Multiple '$purpose' CD Environments are defined. Using the first: " + $cdEnvironment.Id
    }

    return $cdEnvironment
}


function Get-DxaWebApplications($cdEnvironment)
{
    $dxaWebsites = $websites | Where { $_.CdEnvironmentId -eq $cdEnvironment.Id -and $_.ScopedRepositoryKeys -contains $dxaSiteTypeKey}
    if ($dxaWebsites)
    {
        $websiteIds = $dxaWebsites | Select -ExpandProperty Id 
        return Get-TtmWebApplication | Where { $_.WebsiteId -in $websiteIds } 
    }
    else
    {
        do
        {
            do { $baseUrls = Read-Host "Enter DXA '$($cdEnvironment.EnvironmentPurpose)' Website Base URL(s)" }
            until ($baseUrls)
            $baseUrls = $baseUrls.Split(",")
            $website = Add-TtmWebsite -CdEnvironmentId $cdEnvironment.Id -BaseUrls $baseUrls -ErrorVariable cmdletError
        }
        until (!$cmdletError)
        Write-Host ("Website registered with Id '$($website.Id)' and Base URL(s): " + ($baseUrls -join ", "))

        return Get-TtmWebApplication | Where { $_.WebsiteId -eq $website.Id }
    }
}


$stagingOnlyTopologyType = Get-CdTopologyType StagingOnly 'DXA Staging Only' Staging
$stagingLiveTopologyType = Get-CdTopologyType StagingLive 'DXA Staging/Live' Staging,Live

$stagingCdEnvironment = Get-CdEnvironment Staging
if (!$stagingCdEnvironment) { exit }
$stagingDxaWebApps = Get-DxaWebApplications $stagingCdEnvironment
$stagingDxaWebAppIds = $stagingDxaWebApps | Select -ExpandProperty Id

$liveCdEnvironment = Get-CdEnvironment Live
if ($liveCdEnvironment)
{
    $liveDxaWebApps = Get-DxaWebApplications $liveCdEnvironment
    $liveDxaWebAppIds = $liveDxaWebApps | Select -ExpandProperty Id
}

$stagingOnlyTopology = Get-CdTopology DxaStagingOnly 'DXA Development' 'DXA Development' $stagingOnlyTopologyType.Id $stagingCdEnvironment.Id
if ($liveCdEnvironment)
{
    $stagingLiveTopology = Get-CdTopology DxaStagingLive 'DXA Staging/Live' 'DXA Staging/Live' $stagingLiveTopologyType.Id $stagingCdEnvironment.Id,$liveCdEnvironment.Id
}

Write-Host ("Applying Site Type Keys '$dxaSiteTypeKey' and '$dxaExampleSiteKey' to DXA Web Applications: " + ((@($stagingDxaWebAppIds) + @($liveDxaWebAppIds)) -join ", "))
Add-TtmSiteTypeKey $dxaSiteTypeKey -CdTopologyId $stagingOnlyTopology.Id -WebApplicationIds $stagingDxaWebAppIds | Out-Null
Add-TtmSiteTypeKey $dxaExampleSiteKey -CdTopologyId $stagingOnlyTopology.Id -WebApplicationIds $stagingDxaWebAppIds | Out-Null
if ($stagingLiveTopology)
{
    Add-TtmSiteTypeKey $dxaSiteTypeKey -CdTopologyId $stagingLiveTopology.Id -WebApplicationIds $liveDxaWebAppIds | Out-Null
    Add-TtmSiteTypeKey $dxaExampleSiteKey -CdTopologyId $stagingLiveTopology.Id -WebApplicationIds $liveDxaWebAppIds | Out-Null
}

Write-Host "Done."