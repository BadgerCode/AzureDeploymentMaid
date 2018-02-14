param (   
    [Parameter(Mandatory=$true)]
    [string] $subscriptionId,

    [Parameter(Mandatory=$true)]
    [string] $resourceGroupNamePattern,

    [Parameter(Mandatory=$false)]
    [string] $ignoredResourceGroups,

    [Parameter(Mandatory=$false)]
    [string] $maxAgeDays = 30,

    [Parameter(Mandatory=$false)]
    [string] $maxDeploymentsPerGroup = 800,

    [Parameter(Mandatory=$false)]
    [switch] $delete = $false,

    [Parameter(Mandatory=$false)]
    [switch] $skipLogin = $false,

    [Parameter(Mandatory=$false)]
    [switch] $ignoreAge = $false
)

function GetDuration($startTime){
    return [math]::Round(([datetime]::UtcNow - $startTime).TotalMilliseconds)
}


if($skipLogin -eq $true)
{
    Get-AzureRmSubscription -SubscriptionId $subscriptionId | Set-AzureRmContext
}
else {
    Login-AzureRmAccount -SubscriptionId $subscriptionId
}

$maxAge = [datetime]::UtcNow.AddDays(-$maxAgeDays)

$startTime = [datetime]::UtcNow
Write-Host "Start time: $($startTime.ToString('u'))`n"

$rawResourceGroups = Get-AzureRmResourceGroup | Where-Object ResourceGroupName -Like $resourceGroupNamePattern

if([string]::IsNullOrWhiteSpace($ignoredResourceGroups) -eq $false){
    $sanitisedGroupNames = @($ignoredResourceGroups.Split(",") `
        | ForEach-Object { [string]::Concat("^", $_.Trim(), "$") });
    $ignoredResourceGroupsPattern = [string]::Join("|", $sanitisedGroupNames);

    $rawResourceGroups = $rawResourceGroups | Where-Object ResourceGroupName -NotMatch $ignoredResourceGroupsPattern
}

Write-Host "Found resource groups:"
$rawResourceGroups | ForEach-Object { Write-Host $_.ResourceGroupName }
Write-Host "Duration: $(GetDuration -startTime $startTime)ms`n`n"; $startTime = [datetime]::UtcNow

$resourceGroups = @()

foreach($resourceGroup in $rawResourceGroups){
    $resourceGroupName = $resourceGroup.ResourceGroupName

    Write-Host "Checking $resourceGroupName"

    $deployments = Get-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroupName | Sort-Object { $_.Timestamp }
    $totalDeployments = $deployments.Count
    Write-Host "Found $totalDeployments deployments."

    $deploymentsToDelete = @()

    if($ignoreAge -eq $false){
        $deploymentsToDelete = $deployments | Where-Object { $_.Timestamp -le $maxAge }
        $oldDeploymentsCount = $deploymentsToDelete.Count
        Write-Host "Found $oldDeploymentsCount deployments before $($maxAge.ToString()) to delete."
    }

    $extraItemsToDelete = $totalDeployments - $deploymentsToDelete.Count - $maxDeploymentsPerGroup
    if($extraItemsToDelete -gt 0){
        Write-Host "$resourceGroupName has too many deployments (Max allowed: $maxDeploymentsPerGroup). Adding $extraItemsToDelete deployments to delete."

        $deploymentsToDelete = $deployments[0..($deploymentsToDelete.Count + $extraItemsToDelete - 1)]
    }

    if($deploymentsToDelete.Count -eq 0){
        Write-Host "No deployments to delete. Ignoring $resourceGroupName."
    }
    else {
        Write-Host "Adding $resourceGroupName to cleanup queue."
        $resourceGroups += @{ 
            Name=$resourceGroupName; 
            TotalDeployments=$deployments.Count; 
            DeploymentsToDeleteCount=$deploymentsToDelete.Count; 
            Deployments=$deploymentsToDelete;
        }
    }

    Write-Host
}

$resourceGroups = $resourceGroups | Sort-Object -Descending { $_.DeploymentsToDeleteCount }

$grandTotalDeletions = 0
$position = 1;
Write-Host "Cleanup Queue:"
foreach($resourceGroup in $resourceGroups){
    $resourceGroupName = $resourceGroup.Name
    $totalDeployments = $resourceGroup.TotalDeployments
    $deleteCount = $resourceGroup.DeploymentsToDeleteCount

    Write-Host "$position : $resourceGroupName ($totalDeployments deployments. Deleting $deleteCount)"

    $position = $position + 1
    $grandTotalDeletions = $grandTotalDeletions + $deleteCount
}
Write-Host "Duration: $(GetDuration -startTime $startTime)ms`n"; $startTime = [datetime]::UtcNow
Write-Host "Total to delete: $grandTotalDeletions`n`n"

if($delete -eq $false){
    return;
}

foreach($resourceGroup in $resourceGroups){
    $resourceGroupName = $resourceGroup.Name
    $resourceGroupStartTime = [datetime]::UtcNow

    Write-Host "Deleting $($resourceGroup.DeploymentsToDeleteCount) deployments from $resourceGroupName"
    foreach($deployment in $resourceGroup.Deployments){
        $deploymentName = $deployment.DeploymentName

        $result = Remove-AzureRmResourceGroupDeployment -ResourceGroupName $resourceGroupName -DeploymentName $deploymentName
        Write-Host "[$([datetime]::UtcNow.ToString("u"))] Deleted $($deployment.DeploymentName) [$($deployment.Timestamp)]"
    }
    Write-Host "`nResource Group Duration: $(GetDuration -startTime $resourceGroupStartTime)ms`n"
}

Write-Host "Total Deletion Duration: $(GetDuration -startTime $startTime)ms`n"
