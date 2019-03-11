# Catalog Item <-> Entitlement Repair (CIER) Utility
# Author: Ken Gould (ken.gould@dell.com)
# Provided with zero warranty! Please test before using in anger!
# Version 2
#
# Change Log:
#
# v2
#	Added ability to record Resource Actions to Entitlement Relationships and repair them after upgrade
#	Moved to environment variables vs cloudclient.properties file to reduce setup effort
#	General Code clean up
# v1
#	Initial Release
####################################### USER EDITABLE PARAMETERS ######################################

#vRA Details
$vra_address= "ChangeMe.ChangeMe.ChangeMe" #FQDN Formant
$vra_user = "ChangeMe@ChangeMe.ChangeMe" #UPN Format
$vra_password = "ChangeMe"
$vra_tenant = "ChangeMe"

#Folder Locations
$cloudclient_folder = ".\VMware_vRealize_CloudClient-4.5.0-8227624\bin"
$base_folder = ".\"

#File Names
$specific_catalog_items_file = "catalog_items_to_process.txt"
$specific_resource_actions_file = "resource_actions_to_process.txt"

################################### SYSTEM PARAMETERS: DO NOT EDIT ####################################

#CloudClient Variables
$env:vra_server = $vra_address
$env:vra_username = $vra_user
$env:vra_tenant = $vra_tenant
$env:vra_password = $vra_password
$cloud_client_test_file = $base_folder+"cloud_client_test.txt"

#System files
$resource_action_ids_file = "resource_action_ids.resourceactionids"
$entitlement_list_file = "Entitlement-List.entitlement"

#Composite Paths
$cache_folder = $base_folder+"cache\"
$backup_folder = $base_folder+"backup\"
$specific_catalog_items_filepath = $base_folder+$specific_catalog_items_file
$specific_resource_actions_filepath = $base_folder+$specific_resource_actions_file
$cached_entitlement_list = $cache_folder+$entitlement_list_file

#Security Parameters
$Key = (3,4,2,3,56,34,254,222,1,1,2,23,42,54,33,233,1,34,2,7,6,5,35,43)
$vra_secure_password = ConvertTo-SecureString $vra_password -AsPlainText -Force

########################################## PROPRIETARY FUNCTIONS: DO NOT EDIT ##########################################


Function ConnectVRAServer
{
	Connect-vRAServer -Server $vra_address -Tenant $vra_tenant -username $vra_user -password $vra_secure_password | Out-Null
}

Function DisconnectVRAServer
{
	Disconnect-vRAServer -confirm:$false | Out-Null
}

#Discovers all Current Entitlements, and records to new version of entitlements file
Function DiscoverEntitlements ($message)
{
	If (Test-Path -path $cached_entitlement_list)
	{
		Remove-Item $cached_entitlement_list
	}
	Write-Host " $message Local Cache of vRA Entitlements: "  -foregroundcolor white -nonewline
	$get_entitlement_list = "$cloudclient_folder\CloudClient.bat vra entitlement list --format JSON --export $cached_entitlement_list"
	Invoke-expression $get_entitlement_list | out-null
	Write-Host "Done"  -foregroundcolor green
}

#Discovers all Current Resource Action Names and IDs, and records to new version of resource action IDs file
Function DiscoverResourceActionIDS ($message)
{
	$filepath = $cache_folder+$resource_action_ids_file
	If (Test-Path -path $filepath)
	{
		Remove-Item $filepath
	}
	$resource_action_details_hashtable = New-Object -TypeName System.Collections.Hashtable
	Write-Host " $message Local Cache of Resource Action IDs: "  -foregroundcolor white -nonewline
	$resource_action_details_hashtable = Get-vRAResourceOperation | Select Name, ExternalId
	$content_to_save = $resource_action_details_hashtable |convertto-json
	Add-Content -path $filepath -value $content_to_save
	Write-Host "Done"  -foregroundcolor green
}

#Loads entitlements from local cache
Function LoadEntitlements
{
	$array_of_entitlements = @()
	$array_of_entitlements = Get-content $cached_entitlement_list | convertfrom-json
	return $array_of_entitlements
}

#Loads resource action names/ids from local cache
Function LoadResourceActions
{
	$filepath = $cache_folder+$resource_action_ids_file
	$resource_action_array = Get-content $filepath | convertfrom-json
	return $resource_action_array
}

#Loads list of catalog items to be manipulated
Function LoadSpecificCatalogItemsToProcess
{
	$catalog_items_to_process = @()
	$catalog_items_to_process = Get-content $specific_catalog_items_filepath
	return $catalog_items_to_process
}

#Loads list of resource actions to be manipulated
Function LoadSpecificResourceActionsToProcess
{
	$resource_actions_to_process = @()
	$resource_actions_to_process = Get-content $specific_resource_actions_filepath
	return $resource_actions_to_process
}

#Parses entitlements and records current catalog item to entitlement relationships, for later examination of system after upgrade
Function RecordCatalogToEntitlementsRelationshipsForSpecificCatalogItems
{
	Write-Host " Recording CatalogItem <-> Entitlement Relationship for Specified Catalog Items: "  -foregroundcolor white -nonewline
	$entitlements = LoadEntitlements
	$catalogitems = LoadSpecificCatalogItemsToProcess

	Foreach ($catalogitem in $catalogitems)
	{
		$catalog_item_filename = $cache_folder + $catalogitem + "-Entitlement-Relationship.catalogitem"
		If (Test-Path $catalog_item_filename)
		{
			Remove-Item $catalog_item_filename
		}
		Foreach ($entitlement in $entitlements)
		{
			If ($entitlement.entitledCatalogItems.catalogItemRef.label -contains $catalogitem)
			{
				Add-content -path $catalog_item_filename -value $entitlement.name
			}

		}
	}
	Write-Host "Done"  -foregroundcolor green
}

#Parses entitlements and records current resource action to entitlement relationships, for later examination of system after upgrade
Function RecordResourceActionToEntitlementsRelationshipsForSpecificResourceActions
{
	Write-Host " Recording Resource Action <-> Entitlement Relationship for Specified Resource Actions: "  -foregroundcolor white -nonewline
	$entitlements = LoadEntitlements
	$resourceactions = LoadSpecificResourceActionsToProcess

	Foreach ($resourceaction in $resourceactions)
	{
		$resource_action_filename = $cache_folder + $resourceaction + "-Entitlement-Relationship.resourceaction"
		If (Test-Path $resource_action_filename)
		{
			Remove-Item $resource_action_filename
		}
		Foreach ($entitlement in $entitlements)
		{
			If ($entitlement.entitledResourceOperations.resourceOperationRef.label -contains $resourceaction)
			{
				Add-content -path $resource_action_filename -value $entitlement.name
			}

		}
	}
	Write-Host "Done"  -foregroundcolor green
}

#Compares current entitlement cache against historic record of catalog item to entitlement relationship and flags broken relationships
Function ValidateEntitlementsforSpecificCatalogItemsAfterUpgrade
{
	$catalogitems = LoadSpecificCatalogItemsToProcess
	$entitlements_after_upgrade = LoadEntitlements

	Foreach ($catalogitem in $catalogitems)
	{
		Write-Host " "
		Write-Host -foregroundcolor white -nonewline " Checking Catalog Item: "
		Write-Host -foregroundcolor cyan $catalogitem
		$catalog_item_filename = $cache_folder + $catalogitem + "-Entitlement-Relationship.catalogitem"
		$desired_entitlements = @()
		$desired_entitlements = get-content $catalog_item_filename
		Foreach ($desired_entitlement in $desired_entitlements)
		{
			Write-Host -foregroundcolor white -nonewline " Presence in Entitlement "
			Write-Host -foregroundcolor yellow -nonewline $desired_entitlement
			Write-Host -foregroundcolor white -nonewline ": "
			$entitlement_to_be_verified = $entitlements_after_upgrade | where {$_.name -eq $desired_entitlement}
			If ($entitlement_to_be_verified.entitledCatalogItems.catalogItemRef.label -contains $catalogitem)
			{
				Write-Host -foregroundcolor green "Intact"
			}
			else
			{
				Write-Host -foregroundcolor red "Broken"
			}
		}
	}

}

#Compares current entitlement cache against historic record of resource action to entitlement relationship and flags broken relationships
Function ValidateEntitlementsforSpecificResourceActionsAfterUpgrade
{
	$resourceactions = LoadSpecificResourceActionsToProcess
	$entitlements_after_upgrade = LoadEntitlements

	Foreach ($resourceaction in $resourceactions)
	{
		Write-Host " "
		Write-Host -foregroundcolor white -nonewline " Checking Resource Action: "
		Write-Host -foregroundcolor cyan $resourceaction
		$resource_action_filename = $cache_folder + $resourceaction + "-Entitlement-Relationship.resourceaction"
		$desired_entitlements = @()
		$desired_entitlements = get-content $resource_action_filename
		Foreach ($desired_entitlement in $desired_entitlements)
		{
			Write-Host -foregroundcolor white -nonewline " Presence in Entitlement "
			Write-Host -foregroundcolor yellow -nonewline $desired_entitlement
			Write-Host -foregroundcolor white -nonewline ": "
			$entitlement_to_be_verified = $entitlements_after_upgrade | where {$_.name -eq $desired_entitlement}
			If ($entitlement_to_be_verified.entitledResourceOperations.resourceOperationRef.label -contains $resourceaction)
			{
				Write-Host -foregroundcolor green "Intact"
			}
			else
			{
				Write-Host -foregroundcolor red "Broken"
			}
		}
	}

}

#Compares current entitlement cache against historic record of catalog item to entitlement relationship and repairs broken relationships
Function RepairEntitlementsforSpecificCatalogItemsAfterUpgrade
{
	$catalogitems = LoadSpecificCatalogItemsToProcess
	$entitlements_after_upgrade = LoadEntitlements

	Foreach ($catalogitem in $catalogitems)
	{
		Write-Host " "
		Write-Host -foregroundcolor white -nonewline " Checking Catalog Item: "
		Write-Host -foregroundcolor cyan $catalogitem
		$catalog_item_filename = $cache_folder + $catalogitem + "-Entitlement-Relationship.catalogitem"
		$desired_entitlements = @()
		$desired_entitlements = get-content $catalog_item_filename
		Foreach ($desired_entitlement in $desired_entitlements)
		{
			Write-Host -foregroundcolor white -nonewline " Presence in Entitlement "
			Write-Host -foregroundcolor yellow -nonewline $desired_entitlement
			Write-Host -foregroundcolor white -nonewline ": "
			$entitlement_to_be_verified = $entitlements_after_upgrade | where {$_.name -eq $desired_entitlement}
			If ($entitlement_to_be_verified.entitledCatalogItems.catalogItemRef.label -contains $catalogitem)
			{
				Write-Host -foregroundcolor green "Intact"
			}
			else
			{
				$catalogitem_object = Get-vRACatalogItem -name $catalogitem
				Set-vRAEntitlementCustom -id $entitlement_to_be_verified.id -NonEntitledCatalogItems $catalogitem_object.name -Confirm:$false | Out-Null
				Write-Host -foregroundcolor magenta "Repaired"
			}
		}
	}

}

#Compares current entitlement cache against historic record of resource action to entitlement relationship and repairs broken relationships
Function RepairEntitlementsforSpecificResourceActionsAfterUpgrade
{
	$resourceactions = LoadSpecificResourceActionsToProcess
	$entitlements_after_upgrade = LoadEntitlements
	$resource_action_id_array = LoadResourceActions
	Foreach ($resourceaction in $resourceactions)
	{
		Write-Host " "
		Write-Host -foregroundcolor white -nonewline " Checking Resource Action: "
		Write-Host -foregroundcolor cyan $resourceaction
		$resource_action_filename = $cache_folder + $resourceaction + "-Entitlement-Relationship.resourceaction"
		$desired_entitlements = @()
		$desired_entitlements = get-content $resource_action_filename
		Foreach ($desired_entitlement in $desired_entitlements)
		{
			Write-Host -foregroundcolor white -nonewline " Presence in Entitlement "
			Write-Host -foregroundcolor yellow -nonewline $desired_entitlement
			Write-Host -foregroundcolor white -nonewline ": "
			$entitlement_to_be_verified = $entitlements_after_upgrade | where {$_.name -eq $desired_entitlement}
			If ($entitlement_to_be_verified.entitledResourceOperations.resourceOperationRef.label -contains $resourceaction)
			{
				Write-Host -foregroundcolor green "Intact"
			}
			else
			{
				Foreach ($resource_action_id in $resource_action_id_array)
				{
					If ($resource_action_id.name -eq $resourceaction)
					{
						$resource_action_external_id = $resource_action_id.externalid
					}
				}
				Set-vRAEntitlementCustom -id $entitlement_to_be_verified.id -EntitledResourceOperations $resource_action_external_id -Confirm:$false | Out-Null
				Write-Host -foregroundcolor magenta "Repaired"
			}
		}
	}
}

#backs up cache to backup folder, only if a backup of that filetype has not been done before
Function BackupCache ($filetype)
{
	$existing_files = Get-item $backup_folder"\*"$filetype
	If (!($existing_files))
	{
		Copy-item -Force -Recurse $cache_folder"\*."$filetype -Destination $backup_folder
	}
}

#waits for user to press a key before returning to menu
Function anyKey 
{
    Write-Host ""
	Write-Host -NoNewline -Object ' Press any key to return to the main menu...' -ForegroundColor yellow 
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    Menu
}

#waits for user to press a key but does not return to menu
Function AnyKeyToContinue 
{
    Write-Host ""
	Write-Host -NoNewline -Object ' Press any key to continue...' -ForegroundColor yellow 
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
}

#Runs the main menu
Function Menu 
{
    Clear-Host         
    Do
    {
        Clear-Host                                                                        
        Write-Host -Object ''
		Write-Host -Object " Catalog Item / Resource Action <-> Entitlement Repair (CIER) Utility (Please choose an option):" -Foregroundcolor Yellow
        Write-Host -Object ' ************************************************************************************************' -Foregroundcolor Yellow
        Write-Host -Object ' Pre-Upgrade Operations:' -Foregroundcolor cyan
        Write-Host -Object ''	
        Write-Host -Object ' C.  Capture Entitlements & Resource Action IDs. Record Catalog Item / Resource Action <-> Entitlement Relationships'
		Write-Host -Object ' '
		Write-Host -Object ' Post-Upgrade Operations:' -Foregroundcolor cyan
        Write-Host -Object ''	
        Write-Host -Object ' V.  Validate Catalog Item / Resource Action <-> Entitlement Relationships (for specified items & actions)'
        Write-Host -Object ''
		Write-Host -Object ' R.  Repair Broken Catalog Item / Resource Action <-> Entitlement Relationships (for specified items & actions)'
        Write-Host -Object ''
		Write-Host -Object ' Miscellaneous Operations:' -Foregroundcolor cyan
        Write-Host -Object ''
        Write-Host -Object ' X.  Exit'
		Write-Host -Object $errout
        $Menu = Read-Host -Prompt ' (Enter C, V, R or X to Exit)'
        switch ($Menu) 
        {
            C
            {
                Write-Host " "
				Write-Host " Creating Entitlement Cache" -foregroundcolor cyan
				Write-Host " ***************************" -foregroundcolor cyan
				DiscoverEntitlements "Creating"
				BackupCache "entitlement"
				ConnectVRAServer
				DiscoverResourceActionIDS "Creating"
				DisconnectvRAServer
				BackupCache "resourceactionids"
				RecordCatalogToEntitlementsRelationshipsForSpecificCatalogItems
				BackupCache "catalogitem"
				RecordResourceActionToEntitlementsRelationshipsForSpecificResourceActions
				BackupCache "resourceaction"
                anyKey
            }
			V
			{
				Write-Host " "
				Write-Host " Validating Catalog Item / Resource Action <-> Entitlement Relationships" -foregroundcolor cyan
				Write-Host " ************************************************************************" -foregroundcolor cyan
				DiscoverEntitlements "Updating"
				ConnectVRAServer
				DiscoverResourceActionIDS "Updating"
				DisconnectvRAServer
				ValidateEntitlementsforSpecificCatalogItemsAfterUpgrade
				ValidateEntitlementsforSpecificResourceActionsAfterUpgrade
				anyKey
			}
			R
			{
				Write-Host " "
				Write-Host " Repairing Broken Catalog Item / Resource Action <-> Entitlement Relationships" -foregroundcolor cyan
				Write-Host " ******************************************************************************" -foregroundcolor cyan
				DiscoverEntitlements "Updating"
				ConnectvRAServer
				DiscoverResourceActionIDS "Updating"
				RepairEntitlementsforSpecificCatalogItemsAfterUpgrade
				RepairEntitlementsforSpecificResourceActionsAfterUpgrade
				DisconnectvRAServer
				anyKey
			}
			X
			{
				Write-Host " "
				Write-Host " Exiting utility. Thanks for using." -foregroundcolor cyan
				Write-Host " "
				Exit
			}
			default  
            {
                $errout = ' Invalid option please try again........Try C, V, R or X only'
            }
        }
    }
    until ($Menu -eq 'X')
}

########################## IMPORTED / TWEAKED VMWARE FUNCTIONS: DO NOT EDIT ###########################

#Modified from default to allow passing of NonEntitledCatalogItems
Function Set-vRAEntitlementCustom {
<#
    .SYNOPSIS
    Update an existing entitlement

    .DESCRIPTION
    Update an existing entitlement

    .PARAMETER Id
    The id of the entitlement

    .PARAMETER Name
    The name of the entitlement

    .PARAMETER Description
    A description of the entitlement

    .PARAMETER Principals
    Users or groups that will be associated with the entitlement

    .PARAMETER EntitledCatalogItems
    One or more entitled catalog item (works only executing user is already entitled to said catalog item)
	
	.PARAMETER NonEntitledCatalogItems
    One or more non entitled catalog item (works even if executing user is not already entitled to said catalog item)

    .PARAMETER EntitledResourceOperations
    The externalId of one or more entitled resource operation (e.g. Infrastructure.Machine.Action.PowerOn)
	
    .PARAMETER EntitledServices
    One or more entitled service 

    .PARAMETER Status
    The status of the entitlement. Accepted values are ACTIVE and INACTIVE

    .PARAMETER LocalScopeForActions
    Determines if the entitled actions are entitled for all applicable service catalog items or only
    items in this entitlement

    .INPUTS
    System.String.

    .OUTPUTS
    System.Management.Automation.PSObject

    .EXAMPLE
    Set-vRAEntitlement -Id "e5cd1c84-3b76-4ae9-9f2e-35114da6cfd2" -Name "Updated Name"

    .EXAMPLE
    Set-vRAEntitlement -Id "e5cd1c84-3b76-4ae9-9f2e-35114da6cfd2" -Name "Updated Name" -Description "Updated Description" -Principals "user@vsphere.local" -EntitledCatalogItems "Centos" -EntitledServices "A service" -EntitledResourceOperations "Infrastructure.Machine.Action.PowerOff" -Status ACTIVE

    .EXAMPLE
    Get-vRAEntitlement -Name "Entitlement 1" | Set-vRAEntitlement -Description "Updated description!"

#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact="High")][OutputType('System.Management.Automation.PSObject')]

    Param (

        [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$Id,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [String]$Name,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [String]$Description,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [String[]]$Principals,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [String[]]$EntitledCatalogItems,
		
		[Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [String[]]$NonEntitledCatalogItems,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [String[]]$EntitledResourceOperations,
		
        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [String[]]$EntitledServices,

        [Parameter(Mandatory=$false)]
        [ValidateSet("ACTIVE","INACTIVE")]
        [String]$Status,

        [Parameter(Mandatory=$false)]
        [ValidateNotNullOrEmpty()]
        [bool]$LocalScopeForActions

    )    

    Begin {
    
    }
    
    Process {

        try {

            Write-Verbose -Message "Testing for existing entitlement"

            $URI = "/catalog-service/api/entitlements/$($Id)"

            $Entitlement = Invoke-vRARestMethod -URI $URI -Method Get

            # --- Update name
            if ($PSBoundParameters.ContainsKey("Name")){

            Write-Verbose -Message "Updating Name: $($Entitlement.name) >> $($Name)"
            $Entitlement.name = $Name

            }

            # --- Update description
            if ($PSBoundParameters.ContainsKey("Description")){

            Write-Verbose -Message "Updating Description: $($Entitlement.description) >> $($Description)"
            $Entitlement.description = $Description

            }

            # --- Update principals
            if ($PSBoundParameters.ContainsKey("Principals")) {

                foreach($Principal in $Principals) {

                    Write-Verbose -Message "Adding principal: $($Principal)"

                    $CatalogPrincipal = Get-vRACatalogPrincipal -Id $Principal

                    $Entitlement.principals += $CatalogPrincipal


                }

            }
                
            # --- Update entitled catalog items
            if ($PSBoundParameters.ContainsKey("EntitledCatalogItems")) {

                foreach($CatalogItem in $EntitledCatalogItems) {

                    Write-Verbose "Adding entitled catalog item: $($CatalogItem)"

                    # --- Build catalog item ref object
                    $CatalogItemRef = [PSCustomObject] @{

                        id = $((Get-vRAEntitledCatalogItem -Name $CatalogItem).Id)
                        label = $null

                    }
                        
                    # --- Build entitled catalog item object and insert catalogItemRef
                    $EntitledCatalogItem = [PSCustomObject] @{

                    approvalPolicyId = $null
                    active = $null
                    catalogItemRef = $CatalogItemRef

                    }

                    $Entitlement.entitledCatalogItems += $EntitledCatalogItem

                }

            }
			
			# --- Update entitled catalog items with catalog item user is not entitled to already
            if ($PSBoundParameters.ContainsKey("NonEntitledCatalogItems")) {

                foreach($CatalogItem in $NonEntitledCatalogItems) {

                    Write-Verbose "Adding non entitled catalog item: $($CatalogItem)"

                    # --- Build catalog item ref object
                    $CatalogItemRef = [PSCustomObject] @{

                        id = $((Get-vRACatalogItem -Name $CatalogItem).Id)
                        label = $null

                    }
                        
                    # --- Build entitled catalog item object and insert catalogItemRef
                    $EntitledCatalogItem = [PSCustomObject] @{

                    approvalPolicyId = $null
                    active = $null
                    catalogItemRef = $CatalogItemRef

                    }

                    $Entitlement.entitledCatalogItems += $EntitledCatalogItem

                }

            }

            # ---  Update entitled services             
            if ($PSBoundParameters.ContainsKey("EntitledServices")) {

                foreach($Service in $EntitledServices) {

                    Write-Verbose -Message "Adding service: $($Service)"

                    # --- Build service ref object
                    $ServiceRef = [PSCustomObject] @{

                    id = $((Get-vRAService -Name $Service).Id)
                    label = $null

                    }
                        
                    # --- Build entitled service object and insert serviceRef
                    $EntitledService = [PSCustomObject] @{

                        approvalPolicyId = $null
                        active = $null
                        serviceRef = $ServiceRef

                    }

                    $Entitlement.entitledServices += $EntitledService

                }

            }

            # --- Update entitled resource operations
            if ($PSBoundParameters.ContainsKey("EntitledResourceOperations")) {

                foreach ($ResourceOperation in $EntitledResourceOperations) {

                    Write-Verbose -Message "Adding resouceoperation: $($resourceOperation)"

                    $Operation = Get-vRAResourceOperation -ExternalId $ResourceOperation

                    $ResourceOperationRef = [PSCustomObject] @{

                        id = $Operation.Id
                        label = $null

                    }

                    $EntitledResourceOperation = [PSCustomObject] @{

                        approvalPolicyId =  $null
                        resourceOperationType = "ACTION"
                        externalId = $Operation.ExternalId
                        active = $true
                        resourceOperationRef = $ResourceOperationRef
                        targetResourceTypeRef = $Operation.TargetResourceTypeRef

                    }

                    $Entitlement.entitledResourceOperations += $EntitledResourceOperation

                }

            }

            # --- Update status
            if ($PSBoundParameters.ContainsKey("Status")) {

                Write-Verbose -Message "Updating Status: $($Entitlement.status) >> $($Status)"
                $Entitlement.status = $Status

            }

            # --- Update LocalScopeForActions
            if ($PSBoundParameters.ContainsKey("LocalScopeForActions")) {

                Write-Verbose -Message "Updating LocalScopeForActions: $($Entitlement.localScopeForActions) >> $($LocalScopeForActions)"
                $Entitlement.localScopeForActions = $LocalScopeForActions

            }
            # --- Convert the modified entitlement to json 
            $Body = $Entitlement | ConvertTo-Json -Depth 50 -Compress

            if ($PSCmdlet.ShouldProcess($Id)){

                $URI = "/catalog-service/api/entitlements/$($Id)"
                
                # --- Run vRA REST Request
                Invoke-vRARestMethod -Method PUT -URI $URI -Body $Body -Verbose:$VerbosePreference | Out-Null

                # --- Output the Successful Result
                Get-vRAEntitlement -Id $Id
            }

        }
        catch [Exception]{

            throw

        }

    }

    End {

    }

}

########################################## EXECUTION SECTION ##########################################
#Clears screen
Clear-Host

# Enable communication with VMCA signed vCenter
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;

# Add Required PowerCli Modules
Get-Module -ListAvailable VM* | Import-Module
Import-Module VMware.VimAutomation.Cloud

#Check for presence of PowerVRA and install if absent
$powervra_module = Get-InstalledModule -name PowervRA -erroraction 'silentlyContinue'
If (!($powervra_module))
{
	Write-Host "PowervRA not installed: " -foregroundcolor white -nonewline
	Write-Host "Installing: " -foregroundcolor cyan
	Install-Module -name PowervRA -confirm:$false -force
}

#Test for required paths and create if necessary
If(!(Test-Path -path $cache_folder))
{ 
	New-Item -ItemType directory -Path $cache_folder | Out-Null
}

If(!(Test-Path $backup_folder))
{
	New-Item -ItemType directory -Path $backup_folder | Out-Null
}

#Initialize CloudClient if required and start Menu
If (!(Test-Path -path $home\.cloudclient\cloudclient.secure.truststore))
{
	If (Test-Path -path $cloud_client_test_file)
	{
		Remove-Item $cloud_client_test_file
	}
	Write-Host " CloudClient Initialization required. Please follow on-screen prompts to accept EULA and certificates as required" -foregroundcolor cyan
	AnyKeyToContinue
	$setup_and_test_cloudclient = "$cloudclient_folder\CloudClient.bat vra service list --export $cloud_client_test_file"
	Invoke-expression $setup_and_test_cloudclient
	If (Test-Path -path $cloud_client_test_file)
	{
		Clear-Host
		Write-Host " Cloud Client Successfully Initalized" -foregroundcolor green
		Menu
	}
	else
	{
		Clear-Host
		Write-Host " Failed to initalized CloudClient. Please check input variables and vRA system health" -foregroundcolor magenta
		AnyKeyToContinue
		Exit
	}
}
Else
{
	Menu
}


