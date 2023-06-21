#region Functions
function Add-GraphApiRoleToMSI {
    [cmdletbinding()]
    param (
        [parameter(Mandatory = $true)]
        [string]$ApplicationName,

        [parameter(Mandatory = $true)]
        [string[]]$GraphApiRole,

        [parameter(mandatory = $true)]
        [string]$Token
    )

    $baseUri = 'https://graph.microsoft.com/v1.0/servicePrincipals'
    $graphAppId = '00000003-0000-0000-c000-000000000000'
    $spSearchFiler = '"displayName:{0}" OR "appId:{1}"' -f $ApplicationName, $graphAppId

    try {
        $msiParams = @{
            Method  = 'Get'
            Uri     = '{0}?$search={1}' -f $baseUri, $spSearchFiler
            Headers = @{Authorization = "Bearer $Token"; ConsistencyLevel = "eventual" }
        }
        $spList = (Invoke-RestMethod @msiParams).Value
        $msiId = ($spList | Where-Object { $_.displayName -eq $applicationName }).Id
        $graphId = ($spList | Where-Object { $_.appId -eq $graphAppId }).Id

        $msiItemParams = @{
            Method  = 'Get'
            Uri     = "$($baseUri)/$($msiId)?`$expand=appRoleAssignments"
            Headers = @{Authorization = "Bearer $Token"; ConsistencyLevel = "eventual" }
        }
        $msiItem = Invoke-RestMethod @msiItemParams

        $graphRoleParams = @{
            Method  = 'Get'
            Uri     = "$baseUri/$($graphId)/appRoles"
            Headers = @{Authorization = "Bearer $Token"; ConsistencyLevel = "eventual" }
        }
        $graphRoles = (Invoke-RestMethod @graphRoleParams).Value | 
        Where-Object { $_.value -in $GraphApiRole -and $_.allowedMemberTypes -Contains "Application" } |
        Select-Object allowedMemberTypes, id, value
        foreach ($roleItem in $graphRoles) {
            if ($roleItem.id -notIn $msiItem.appRoleAssignments.appRoleId) {
                Write-Host "Adding role ($($roleItem.value)) to identity: $($applicationName).." -ForegroundColor Green
                $postBody = @{
                    "principalId" = $msiId
                    "resourceId"  = $graphId
                    "appRoleId"   = $roleItem.id
                }
                $postParams = @{
                    Method      = 'Post'
                    Uri         = "$baseUri/$graphId/appRoleAssignedTo"
                    Body        = $postBody | ConvertTo-Json
                    Headers     = $msiParams.Headers
                    ContentType = 'Application/Json'
                }
                $result = Invoke-RestMethod @postParams
                if ( $PSBoundParameters['Verbose'] -or $VerbosePreference -eq 'Continue' ) {
                    $result
                }
            }
            else {
                Write-Host "role ($($roleItem.value)) already found in $($applicationName).." -ForegroundColor Yellow
            }
        }
        
    }
    catch {
        Write-Warning $_.Exception.Message
    }
}
#endregion

#region How to use the function
# $params = @{
#     ClientId     = $env:appId
#     TenantId     = $env:tenant
#     ClientSecret = $env:secret | ConvertTo-SecureString -AsPlainText -Force
# }
# $token = Get-MsalToken @params
Connect-AzAccount -Tenant "powers-hell.com" -UseDeviceAuthentication
$token = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com"
$roles = @(
    "DeviceManagementApps.ReadWrite.All", 
    "DeviceManagementConfiguration.Read.All", 
    "DeviceManagementManagedDevices.Read.All", 
    "DeviceManagementRBAC.Read.All", 
    "DeviceManagementServiceConfig.ReadWrite.All", 
    "GroupMember.Read.All"
)
Add-GraphApiRoleToMSI -ApplicationName "PSCONFEU2023QUICKDEMO" -GraphApiRole $roles -Token $token.Token
#endregion