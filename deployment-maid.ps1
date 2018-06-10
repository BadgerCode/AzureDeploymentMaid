param (   
    [Parameter(Mandatory=$true)]
    [string] $subscriptionId,

    [Parameter(Mandatory=$true)]
    [string] $resourceGroupNamePattern,

    [Parameter(Mandatory=$false)]
    [string] $ignoredResourceGroups,

    [Parameter(Mandatory=$false)]
    [double] $maxAgeDays = -1,

    [Parameter(Mandatory=$false)]
    [double] $maxDeploymentsPerGroup = 800,

    [Parameter(Mandatory=$false)]
    [switch] $delete = $false,

    [Parameter(Mandatory=$false)]
    [switch] $skipLogin = $false
)

function GetFormattedDuration($startTime){
    $durationMs = [math]::Round(([datetime]::UtcNow - $startTime).TotalMilliseconds)
    return [timespan]::FromMilliseconds($durationMs).ToString("hh\:mm\:ss\.fff");
}

function PrintFinalStats($startTime){
    Write-Host "Start: $($startTime.ToString('u'))"
    Write-Host "End: $([datetime]::UtcNow.ToString('u'))"
    Write-Host "Duration: $(GetFormattedDuration -startTime $startTime)`n"
}


if($skipLogin -eq $true)
{
    Get-AzureRmSubscription -SubscriptionId $subscriptionId | Set-AzureRmContext
}
else {
    Login-AzureRmAccount -SubscriptionId $subscriptionId
}

$ignoreAge = ($maxAgeDays) -eq -1
$maxAge = [datetime]::UtcNow.AddDays(-$maxAgeDays)

$startTime = [datetime]::UtcNow
$currentOperationStartTime = $startTime
Write-Host "Start time: $($startTime.ToString('u'))`n"

$rawResourceGroups = Get-AzureRmResourceGroup 
$totalResourceGroupsCount = $rawResourceGroups.Count
$rawResourceGroups = $rawResourceGroups | Where-Object ResourceGroupName -Like $resourceGroupNamePattern

if([string]::IsNullOrWhiteSpace($ignoredResourceGroups) -eq $false){
    $sanitisedGroupNames = @($ignoredResourceGroups.Split(",") `
        | ForEach-Object { [string]::Concat("^", $_.Trim(), "$") });
    $ignoredResourceGroupsPattern = [string]::Join("|", $sanitisedGroupNames);

    $rawResourceGroups = $rawResourceGroups | Where-Object ResourceGroupName -NotMatch $ignoredResourceGroupsPattern
}

Write-Host "Found resource groups:"

if($rawResourceGroups.Count -eq 0)
{
    Write-Host "No resource groups found. Check the subscriptionId, resourceGroupNamePattern and ignoredResourceGroups parameters.`n"
    PrintFinalStats -startTime $startTime
    return;
}

$rawResourceGroups | ForEach-Object { Write-Host $_.ResourceGroupName }
Write-Host "(Resource groups not included: $($totalResourceGroupsCount - $rawResourceGroups.Count))"
Write-Host "Duration: $(GetFormattedDuration -startTime $currentOperationStartTime)`n`n"; $currentOperationStartTime = [datetime]::UtcNow


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
Write-Host "Duration: $(GetFormattedDuration -startTime $currentOperationStartTime)`n`n"; $currentOperationStartTime = [datetime]::UtcNow


Write-Host "Cleanup Queue:"

if($resourceGroups.Count -eq 0)
{
    Write-Host "No resource groups on the cleanup queue.`n"
    PrintFinalStats -startTime $startTime
    return;
}

$resourceGroups = $resourceGroups | Sort-Object -Descending { $_.DeploymentsToDeleteCount }
$grandTotalDeletions = 0
$position = 1;

foreach($resourceGroup in $resourceGroups){
    $resourceGroupName = $resourceGroup.Name
    $totalDeployments = $resourceGroup.TotalDeployments
    $deleteCount = $resourceGroup.DeploymentsToDeleteCount

    Write-Host "$position : $resourceGroupName ($totalDeployments deployments. Deleting $deleteCount)"

    $position = $position + 1
    $grandTotalDeletions = $grandTotalDeletions + $deleteCount
}
Write-Host "Total to delete: $grandTotalDeletions`n`n"

if($delete -eq $false)
{
    Write-Host "Delete flag not set. Stopping.`n"
    PrintFinalStats -startTime $startTime
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
    Write-Host "`nResource Group Duration: $(GetFormattedDuration -startTime $resourceGroupStartTime)`n"
}

PrintFinalStats -startTime $startTime
