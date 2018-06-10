# Azure Deployment Maid

This is a ```powershell``` script which analyses deployments in resource groups for a subscription.

The purpose of this is to clean up old deployments and avoid hitting the 800 max deployments hard limit per resource group.

By default, this will analyse resource groups but not delete anything. Deletion is enabled via the ```-delete``` flag.

---

## Examples
### Check for deployments older than 30 days for each resource group

```powershell
.\deployment-maid.ps1 `
 -subscriptionId subId `
 -resourceGroupNamePattern "Dev-*" `
 -maxAgeDays 30
```

_Add the ```-delete``` flag to also delete the listed deployments._

### Enforce a maximum of 100 deployments per resource group
```powershell
.\deployment-maid.ps1 `
 -subscriptionId subId `
 -resourceGroupNamePattern "Dev-*" `
 -ignoreAge `
 -maxDeploymentsPerGroup 100 `
 -delete
```

---

## Required Parameters

| Name           | Value | Description |
| -------------- | ----- | ----------- |
| subscriptionId | string  | Azure subscription Id |
| resourceGroupNamePattern | string | Filters resource groups based on their name. Wildcards supported.<br>E.g.<br>A single resource group: ```"MyResourceGroup"```<br>All groups: ```"\*"```<br>All groups starting with Dev-: ```"Dev-\*"```|

## Optional Parameters

| Name      | Value | Description |
| --------- | ----- | ----------- |
| ignoredResourceGroups | String | Comma-separated list of resource groups to ignore. E.g. "Group1, Group2".<br>Applied after finding groups with resourceGroupNamePattern. |
| maxAgeDays | Int  | Deployments older than this will be deleted. Default: 30. Can be disabled via the ```-ignoreAge``` flag |
| maxDeploymentsPerGroup | Int | Ensure that no resource group has more deployments than this. Default: 800 |

## Optional Flags

| Name      | Description |
| --------- | ----------- |
| ignoreAge | Ignore maxAgeDays | 
| delete | Delete highlighted deployments |
| skipLogin | Skip login and use existing session. If running the script multiple times, use this after the first run |



## Notes
* Deployments are deleted from oldest to newest
* Deletions will start with the groups that have the most amount of items to delete
* The names and times of deleted deployments are output as they are deleted
