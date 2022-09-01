#
# Powershell script to deploy the resources - Customer portal, Publisher portal and the Azure SQL Database
#

Param(  
   [string][Parameter(Mandatory)]$WebAppNamePrefix, # Prefix used for creating web applications
   [string][Parameter()]$TenantID, # The value should match the value provided for Active Directory TenantID in the Technical Configuration of the Transactable Offer in Partner Centre
   [string][Parameter()]$ADApplicationID, # The value should match the value provided for Active Directory Application ID in the Technical Configuration of the Transactable Offer in Partner Center
   [string][Parameter()]$ADApplicationSecret, # Secret key of the AD Application
   [string][Parameter()]$ADMTApplicationID # The value should match the value provided for Multi-Tenant Active Directory Application ID in the Technical Configuration of the Transactable Offer in Partner Center
)

Write-Host "Starting SaaS Accelerator Deployment..."

# Make sure to install Az Module before running this script
# Install-Module Az
# Install-Module -Name AzureAD

# Azure Login
if($env:ACC_CLOUD) {
    Write-Host "🔑  Authenticating using device..."
    #Connect-AzAccount -UseDeviceAuthentication
} else {
    Write-Host "🔑  Authenticating using AzAccount authentication..."
    Connect-AzAccount
}


$currentContext = get-AzureRMContext
$currentTenant = $currentContext.Account.ExtendedProperties.Tenants
# Get TenantID if not set as argument
if(!($TenantID)) {    
    Get-AzTenant | Format-Table
    if (!($TenantID = Read-Host "⌨  Type your TenantID or press Enter to accept your current one [$currentTenant]")) { $TenantID = $currentTenant }    
}
else {
    Write-Host "🔑  TenantID provided: $TenantID"
}
                                                   


# Create AAD App Registration

# AAD App Registration - Create Multi-Tenant App Registration Requst
if (!($ADApplicationID)) {   # AAD App Registration - Create Single Tenant App Registration
    Write-Host "🔑  Creating ADApplicationID..."
    $Guid = New-Guid
    $startDate = Get-Date
    $endDate = $startDate.AddYears(2)
    $ADApplicationSecret = ([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(($Guid))))+"="

    try {    
        $ADApplication = New-AzureADApplication -DisplayName "$WebAppNamePrefix-FulfillmentApp"
        $ADObjectID = $ADApplication | %{ $_.ObjectId }
        $ADApplicationID = $ADApplication | %{ $_.AppId }
        Write-Host "🔑  AAD Single Tenant Object ID:" $ADObjectID    
        Write-Host "🔑  AAD Single Tenant Application ID:" $ADApplicationID  
        sleep 5 #this is to give time to AAD to register
        New-AzureADApplicationPasswordCredential -ObjectId $ADObjectID -StartDate $startDate -EndDate $endDate -Value $ADApplicationSecret -InformationVariable "SaaSAPI"
        Write-Host "🔑  ADApplicationID created."
        
    }
    catch [System.Net.WebException],[System.IO.IOException] {
        Write-Host "🚨🚨   $PSItem.Exception"
        break;
    }
}

$restbody = "" +`
"{ \`"displayName\`": \`"$WebAppNamePrefix-LandingpageAppReg\`"," +`
" \`"api\`":{\`"requestedAccessTokenVersion\`": 2}," +`
" \`"signInAudience\`" : \`"AzureADandPersonalMicrosoftAccount\`"," +`
" \`"web\`": " +`
"{ \`"redirectUris\`": " +`
"[" +`
"\`"https://$WebAppNamePrefix-portal.azurewebsites.net\`"," +`
"\`"https://$WebAppNamePrefix-portal.azurewebsites.net/\`"," +`
"\`"https://$WebAppNamePrefix-portal.azurewebsites.net/Home/Index\`"," +`
"\`"https://$WebAppNamePrefix-portal.azurewebsites.net/Home/Index/\`"," +`
"\`"https://$WebAppNamePrefix-admin.azurewebsites.net\`"," +`
"\`"https://$WebAppNamePrefix-admin.azurewebsites.net/\`"," +`
"\`"https://$WebAppNamePrefix-admin.azurewebsites.net/Home/Index\`"," +`
"\`"https://$WebAppNamePrefix-admin.azurewebsites.net/Home/Index/\`"" +`
"]," +`
" \`"logoutUrl\`": \`"https://$WebAppNamePrefix-portal.azurewebsites.net/logout\`"," +`
"\`"implicitGrantSettings\`": " +`
"{ \`"enableIdTokenIssuance\`": true }}," +`
" \`"requiredResourceAccess\`": " +`
" [{\`"resourceAppId\`": \`"00000003-0000-0000-c000-000000000000\`", " +`
" \`"resourceAccess\`": " +`
" [{ \`"id\`": \`"e1fe6dd8-ba31-4d61-89e7-88639da4683d\`"," +`
" \`"type\`": \`"Scope\`" }]}] }" 

Write-Host $restbody

if (!($ADMTApplicationID)) {   # AAD App Registration - Create Multi-Tenant App Registration Requst 
    Write-Host "🔑  Mapping Landing paged mapped to AppRegistration..."
    try {
        $landingpageLoginAppReg = $(az rest --method POST  --headers 'Content-Type=application/json' --uri https://graph.microsoft.com/v1.0/applications --body $restbody | jq '{lappID: .appId, publisherDomain: .publisherDomain, objectID: .id}')
        Write-Host "$landingpageLoginAppReg"
        $ADMTApplicationID = $landingpageLoginAppReg | jq .lappID | %{$_ -replace '"',''}
        Write-Host "🔑  Landing paged mapped to AppRegistration: $ADMTApplicationID"
        $ADMTObjectID = $landingpageLoginAppReg | jq .objectID | %{$_ -replace '"',''}
        Write-Host "🔑  Landing paged AppRegistration ObjectID: $ADMTObjectID"

        # Download Publisher's AppRegistration logo
        if($LogoURLpng) { 
            # Write-Host "📷  Downloading SSO AAD AppRegistration logo image..."
            # Invoke-WebRequest -Uri $LogoURLpng -OutFile "..\..\src\SaaS.SDK.CustomerProvisioning\wwwroot\applogo.png"
            # Write-Host "📷  SSO AAD AppRegistration logo image downloaded."    

            #Write-Host "🔑  Attaching Image to SSO AAD AppRegistration ObjectID: $ADMTObjectID ..."
            #$LogoURLpngPath = $(Resolve-Path "..\..\src\SaaS.SDK.CustomerProvisioning\wwwroot\applogo.png").Path

            #TODO: This is broken in PS CLI:  https://stackoverflow.microsoft.com/questions/276511
            # $LogoByteArray = [System.IO.File]::ReadAllBytes($LogoURLpngPath)
            # Set-AzureADApplicationLogo -ObjectId $ADMTObjectID -ImageByteArray $LogoByteArray 
            # Set-AzureADApplicationLogo -ObjectId $ADMTObjectID -FilePath $LogoURLpngPath
            #Write-Host "🔑  Image attached to SSO AAD AppRegistration."
        }
    }
    catch [System.Net.WebException],[System.IO.IOException] {
        Write-Host "🚨🚨   $PSItem.Exception"
        break;
    }
    Write-Host "🔑  AAD Single Tenant Application ID:" $ADApplicationID  
    Write-Host "🔑  AAD Single Tenant Application Secret:" $ADApplicationSecret  
    Write-Host "🔑  AAD Multi Tenant Application ID:" $ADMTApplicationID  
}
