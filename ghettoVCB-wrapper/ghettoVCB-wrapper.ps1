<#  SCRIPT DETAILS
    .NOTES
    ===============================================================================================================
    .Created By:    Ken Gould
    .Group:         HCI BU
    .Organization:  VMware, Inc.
    .Version:       1.0 (Build 001)
    .Date:          2020-06-17
    ===============================================================================================================
    .CREDITS
    - William Lam - for base of LogMessage Function
    ===============================================================================================================
    .CHANGE_LOG
    - 1.0.000 (Ken Gould / 2020-06-17) - Initial script creation
    ===============================================================================================================
    .DESCRIPTION
        This script helps automate capturing and restoring both a VM via ghettoVCB and also the extra information
        stored in vCenter for that VM including OVF Properties, Inventory Locations and DRS Settings

    .EXAMPLE
        PS C:\> ghettoVCB-wrapper.ps1 -backup -vm vmname -quiesce disabled -esxiRootPassword MyLovelyEsxiPa$$w0rd

    .EXAMPLE
        PS C:\> ghettoVCB-wrapper.ps1 -restore -vm vmname -esxihost myhost01.mydomain.local -esxiRootPassword MyLovelyEsxiPa$$w0rd
        Restores both the VM and the OVF properties on specified host

    .NOTES
        DISCLAIMER: This script it provided for educational purposes. It it is provided without warranty. Please test thoroughly
        before use
#>

Param(
    [Parameter(mandatory=$true)]
    [String]$vm,
    [Parameter(mandatory=$true)]
    [String]$esxiRootPassword,    
    [Parameter(mandatory=$false)]
    [Switch]$backup,
    [Parameter(mandatory=$false)]
    [String]$quiesce,
    [Parameter(mandatory=$false)]
    [Switch]$restore,
    [Parameter(mandatory=$false)]
    [String]$esxiHost,
    [Parameter(mandatory=$false)]
    [Switch]$ovfonly
)

$filetimeStamp = Get-Date -Format "MM-dd-yyyy_HH_mm_ss"   
$Global:logFile = $PSScriptRoot+'\ghettoVCB-wrapper-'+$filetimeStamp+'.log'
$Global:backupLocation = 'backupDatastore/backupFolder'
$Global:targetDatastore = 'targetDatastore'

Function catchWriter
{
    <#
    .SYNOPSIS
        Prints a controlled error message after a failure

    .DESCRIPTION
        Accepts the invocation object from a failure in a Try/Catch block and prints back more precise information regarding
        the cause of the failure

    .EXAMPLE
        catchWriter -object $_
        This example when placed in a catch block will return error message, line number and line text (command) issued

    #>
    Param(
        [Parameter(mandatory=$true)]
        [PSObject]$object
        )
    $lineNumber = $object.InvocationInfo.ScriptLineNumber
    $lineText = $object.InvocationInfo.Line.trim()
    $errorMessage = $object.Exception.Message
    LogMessage "Error at Script Line $lineNumber" Red
    LogMessage "Relevant Command: $lineText" Red
    LogMessage "Error Message: $errorMessage" Red
}

Function LogMessage 
{
    <#
    .SYNOPSIS
        Prints a message on screen including the timestamp of the message.

    .DESCRIPTION
        Allows controlled printing of messages in colour as well as with or without line skip with the inclusion of timestamp

    .EXAMPLE
        LogMessage "Print this messange and this $variable as well as this $($object.property)" Red
        Will print the above in red text after evaluating the variable values, and also include said message in log file

    .NOTES
        Based on LogMessage created by William Lam. Modified to include colour, skipnewline and logging

    #>
    Param(
        [Parameter(Mandatory=$true)]
        [String]$message,
        [Parameter(Mandatory=$false)]
        [String]$colour,
        [Parameter(Mandatory=$false)]
        [string]$skipnewline
    )

    If (!$colour){
        $colour = "green"
    }

    $timeStamp = Get-Date -Format "MM-dd-yyyy_HH:mm:ss"

    Write-Host -NoNewline -ForegroundColor White " [$timestamp]"
    If ($skipnewline)
    {
        Write-Host -NoNewline -ForegroundColor $colour " $message"        
    }
    else 
    {
        Write-Host -ForegroundColor $colour " $message" 
    }
    $logContent = '['+$timeStamp+'] '+$message
    Add-Content -path $logFile $logContent
}

Function Get-VMSettings
{
    <#
    .SYNOPSIS
        Master function to backup all settings for a VM after ghettoVCB backup

    .DESCRIPTION
        Calls several other functions that retrieve different parts of the VM configuration. Assembles all data and saves to a single 
        JSON file

    .EXAMPLE
        Get-VMSettings -vm $vm

    #>
    Param(
    [Parameter(Mandatory=$true)]
    [PSObject]$vm
    )
    $targetFile = $psscriptRoot + "\" + $vm.name + "-settings-backup.json"
    Try
    {
        $vmVappConfig = Get-VMvAppConfig -vm $vmToBackup
        $vmLocations = Get-VMLocations -vm $vmToBackup
        $vmDrsSettings = Get-DRSGroupsAndRules -vm $vmToBackup

        $vmSettingsBackup = @()
            $vmSettingsBackup += [pscustomobject]@{
                'ovfProperties' = $vmVappConfig
                'inventoryLocations' = $vmLocations
                'drsSettings' = $vmDrsSettings
            }
        $vmSettingsBackup | ConvertTo-Json -depth 3 | Out-File $targetFile
        LogMessage -message "Settings saved in $targetFile"
    }
    Catch
    {
        catchWriter -object $_
    }
}

Function Get-VMvAppConfig
{
    <#
    .SYNOPSIS
        Retrieves the full OVF environment settings from a standard VM.

    .DESCRIPTION
        Saves the setting of the passed VM object to a JSON file in the same location as the ghettoVCB-wrapper script

    .EXAMPLE
        Get-VMAppConfig -vm $vm

    #>
    Param(
        [Parameter(Mandatory=$true)]
        [PSObject]$vm
        )
    $targetFile = $psscriptRoot + "\" + $vm.name + "-property-backup.json"
    LogMessage -message "Initating Backup of OVF Properties" -colour yellow
    Try
    {
        If ($vm.ExtensionData.Config.VAppConfig)
        {
            $vmVappConfig = $vm.ExtensionData.Config.VAppConfig #| ConvertTo-Json | Out-File $targetFile
            LogMessage -message "OVF Properties successfully captured"
            return $vmVappConfig
        }
        else 
        {
            LogMessage -message "No OVF properties were detected on $($vm.name). You may ignore this message if this is correct." -colour magenta
        }
    }
    Catch
    {
        catchWriter -object $_
    }
}

Function Get-VMLocations
{
    <#
    .SYNOPSIS
        Retrieves the folder and resource pool settings.

    .DESCRIPTION
        Saves the folder and resource pool settings for the passed VM object to a JSON file in the same location as the ghettoVCB-wrapper script

    .EXAMPLE
        Get-VMLocations -vm $vm

    #>
    Param(
        [Parameter(Mandatory=$true)]
        [PSObject]$vm
        )
    $targetFile = $psscriptRoot + "\" + $vm.name + "-location-backup.json"
    LogMessage -message "Initating Backup of Inventory Location Settings" -colour yellow

    Try
    {
        $vmSettings = @()
        $vmSettings += [pscustomobject]@{
            'folder' = $vm.folder.name
            'resourcePool' = $vm.resourcePool.name
        }
        #$vmSettings | ConvertTo-Json -depth 1 | Out-File $targetFile
        LogMessage -message "VM Locations successfully captured"
        return $vmSettings
    }
    Catch
    {
        catchWriter -object $_
    }
}

Function Get-DRSGroupsAndRules
{
        <#
    .SYNOPSIS
        Retrieves the DRS Groups And Rules for a VM

    .DESCRIPTION
        Saves the DRS Group and Rule settings for the passed VM object to a JSON file in the same location as the ghettoVCB-wrapper script

    .EXAMPLE
        Get-DRSGroupsAndRules -vm $vm

    #>
    Param(
        [Parameter(Mandatory=$true)]
        [PSObject]$vm
        )
    $targetFile = $psscriptRoot + "\" + $vm.name + "-drs-settings-backup.json"
    LogMessage -message "Initating Backup of DRS Group Settings" -colour yellow

    Try
    {
        $retrievedVmDrsGroups = (Get-DrsClusterGroup | Where-Object {$_.member -like $($vm.name)}).name
        $vmDrsGroups = @()
        Foreach ($drsGroup in $retrievedVmDrsGroups)
        {
            $vmDrsGroups += [pscustomobject]@{
            'groupName' = $drsGroup
            }
        }

        $retrievedVmID = (get-vm -name xreg-wsa01c).id
        $retrievedCluster = (Get-VMHost -name $($vm.VMHost.name)).parent.name
        $retrievedDrsRules = (Get-DrsRule -Cluster $retrievedCluster | Where-Object {$_.vmids -like $($vm.id)})
        $vmDrsRules = @()
        Foreach ($drsRule in $retrievedDrsRules)
        {
            Foreach ($vmId in $drsRule.vmids)
            {
                $vmName = (Get-VM -id $vmId).name
                If (!$vmNames)
                {
                    $vmNames += $vmName    
                }
                else 
                {
                    $vmNames += ','+$vmName    
                }
            }
            $vmDrsRules += [pscustomobject]@{
                'name' = $drsrule.name
                'vmNames' = $vmNames
                'keepTogether' = $drsRule.KeepTogether
            }
        }

        $drsBackup += [pscustomobject]@{
            'groups' = $vmDrsGroups
            'rules' = $vmDrsRules
        }

        #$drsBackup | ConvertTo-Json | Out-File $targetFile
        LogMessage -message "VM DRS Groups and Rules successfully captured"
        return $drsBackup
    }
    Catch
    {
        catchWriter -object $_
    }
}

Function New-VMOvfProperty
{
    <#
    .SYNOPSIS
        Create a single OVF Property on a standard VM.

    .DESCRIPTION
        Accepts a object with propery details, parses it and adds it to supplied VM

    .EXAMPLE
        New-VMOvfProperty -vm $vm -property $propertyObject

    #>
    Param(
        [Parameter(Mandatory=$true)]
        [PSObject]$vm,
        [Parameter(Mandatory=$true)]
        [PSObject]$property
        )

    #define spec
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $spec.vAppConfig = New-Object VMware.Vim.VmConfigSpec
    $propertySpec = New-Object VMware.Vim.VAppPropertySpec
    
    #populate spec
    $propertySpec.Operation = "Add"
    $propertySpec.Info = New-Object VMware.Vim.VAppPropertyInfo
    $propertySpec.info.category = $property.category 
    $propertySpec.info.classId = $property.classId
    $propertySpec.info.defaultValue = $property.defaultValue 
    $propertySpec.info.description = $property.description   
    $propertySpec.info.id = $property.id 
    $propertySpec.info.instanceId = $property.instanceId      
    $propertySpec.info.key = $property.key
    $propertySpec.info.label = $property.label   
    $propertySpec.info.type = $property.type 
    $propertySpec.info.typeReference = $property.typeReference 
    $propertySpec.info.userConfigurable = $property.userConfigurable 
    $propertySpec.info.value = $property.value
    $spec.VAppConfig.Property = $propertySpec

    #write spec
    LogMessage -message "Creating OVF Property $($property.id) on $($vm.name)"
    $task = $vm.ExtensionData.ReconfigVM_Task($spec)
    $task1 = Get-Task -Id ("Task-$($task.value)")
    $waitask = $task1 | Wait-Task 
}

Function Set-VMOvfIPAssignment
{
    <#
    .SYNOPSIS
        Sets the IP Assignment OVF Setting

    .DESCRIPTION
        Accepts a object with IP Assigment details and assigns it to the supplied VM

    .EXAMPLE
        Set-VMOvfIPAssignment -vm $vm -assignment $assignmentObject

    #>    
    Param(
        [Parameter(Mandatory=$true)]
        [PSObject]$vm,
        [Parameter(Mandatory=$true)]
        [PSObject]$assignment
        )
    
    #define spec
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $spec.vAppConfig = New-Object VMware.Vim.VmConfigSpec
    $assignmentSpec = New-Object VMware.Vim.VAppIPAssignmentInfo

    #populate spec
    $assignmentSpec.ipAllocationPolicy = $assignment.ipAllocationPolicy
    $assignmentSpec.SupportedAllocationScheme = $assignment.SupportedAllocationScheme
    $assignmentSpec.SupportedIpProtocol = $assignment.SupportedIpProtocol
    $assignmentSpec.IpProtocol = $assignment.IpProtocol
    $spec.vAppConfig.IpAssignment = $assignmentSpec

    #write spec
    LogMessage -message "Configuring IP Assignment setting on $($vm.name)"
    $task = $vm.ExtensionData.ReconfigVM_Task($spec)
    $task1 = Get-Task -Id ("Task-$($task.value)")
    $waitask = $task1 | Wait-Task 
}

Function Set-VMOvfEnvTransport
{
    <#
    .SYNOPSIS
        Sets the Environment Transport setting for OVF properties

    .DESCRIPTION
        Accepts a object with Environment Transport details and assigns it to the supplied VM

    .EXAMPLE
        Set-VMOvfEnvTransport -vm $vm -transport $transportObject

    #>    
    Param(
        [Parameter(Mandatory=$true)]
        [PSObject]$vm,
        [Parameter(Mandatory=$true)]
        [PSObject]$transport
        )

    #define spec
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $spec.vAppConfig = New-Object VMware.Vim.VmConfigSpec

    #populate spec
    $spec.vAppConfig.ovfEnvironmentTransport = $transport
    
    #write spec
    LogMessage -message "Configuring Environment Transport setting on $($vm.name)"
    $task = $vm.ExtensionData.ReconfigVM_Task($spec)
    $task1 = Get-Task -Id ("Task-$($task.value)")
    $waitask = $task1 | Wait-Task 
}

Function New-VMOvfProduct
{
    <#
    .SYNOPSIS
        Create a single OVF Product on a standard VM.

    .DESCRIPTION
        Accepts a object with produt details, parses it and adds it to supplied VM

    .EXAMPLE
        New-VMOvfProduct-vm $vm -product $productObject

    #>

    Param(
        [Parameter(Mandatory=$true)]
        [PSObject]$vm,
        [Parameter(Mandatory=$true)]
        [PSObject]$product
        )

    #define spec
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $spec.vAppConfig = New-Object VMware.Vim.VmConfigSpec
    $productSpec = New-Object VMware.Vim.VAppProductSpec

    #populate spec
    $productSpec.Operation = "Add"
    $productSpec.Info = New-Object VMware.Vim.VAppProductInfo
    $productSpec.info.appUrl = $product.appUrl
    $productSpec.info.classId = $product.classId 
    $productSpec.info.fullVersion = $product.fullVersion 
    $productSpec.info.instanceId = $product.instanceId   
    $productSpec.info.key = $product.key 
    $productSpec.info.name = $product.name 
    $productSpec.info.productUrl = $product.productUrl   
    $productSpec.info.vendor = $product.vendor
    $productSpec.info.vendorUrl = $product.vendorUrl
    $productSpec.info.version = $product.version
    $spec.VAppConfig.Product = $productSpec

    #write spec
    LogMessage -message "Adding Product Setting on $($vm.name)"
    $task = $vm.ExtensionData.ReconfigVM_Task($spec)
    $task1 = Get-Task -Id ("Task-$($task.value)")
    $waitask = $task1 | Wait-Task 
}

Function Set-VMOvfEULA
{
    <#
    .SYNOPSIS
        Sets the EULA setting for OVF properties

    .DESCRIPTION
        Accepts a object with EULA details and assigns it to the supplied VM

    .EXAMPLE
        Set-VMOvfEULA -vm $vm -eula $eulaObject
    #>    

    Param(
    [Parameter(Mandatory=$true)]
    [PSObject]$vm,
    [Parameter(Mandatory=$true)]
    [PSObject]$eula
    )

    #define spec
    $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
    $spec.vAppConfig = New-Object VMware.Vim.VmConfigSpec

    #populate spec
    $spec.vAppConfig.eula = $eula

    #write spec
    LogMessage -message "Setting EULA on $($vm.name)"
    $task = $vm.ExtensionData.ReconfigVM_Task($spec)
    $task1 = Get-Task -Id ("Task-$($task.value)")
    $waitask = $task1 | Wait-Task 
}

Function Add-VMtoEmptyDRSGroup
{
    <#
    .SYNOPSIS
        Adds a single VM to a VM Group

    .DESCRIPTION
        Used when DRS groups is currently empty due to VM having been deleted. Empty DRS groups are technically
        invalid, so this function is used over Set-DrsClusterGroup which expects the group to have at least one 
        current member

    .EXAMPLE
        Add-VMtoEmptyDRSGroup -cluster $cluster -groupName $groupName -vm $vm

    #>
    Param(
        [Parameter(Mandatory=$true)]
        [String]$cluster,
        [Parameter(Mandatory=$true)]
        [String]$groupName,
        [Parameter(Mandatory=$true)]
        [PSObject]$vm
        )

    $clusterObject = Get-Cluster -name $cluster
    
    #define spec
    $spec = New-Object VMware.Vim.ClusterConfigSpecEx
    $spec.groupSpec = New-Object VMware.Vim.ClusterGroupSpec[] (1)
    $spec.groupSpec[0] = New-Object VMware.Vim.ClusterGroupSpec
    
    #populate spec
    $spec.groupSpec[0].Operation = "Edit"
    $spec.groupSpec[0].info = New-Object VMware.Vim.ClusterVmGroup
    $spec.groupSpec[0].info.name = $groupName
    $spec.groupSpec[0].info.vm += $vm.ExtensionData.MoRef

    #write spec
    LogMessage -message "Adding $($vm.name) to $groupName"
    $task = $clusterObject.ExtensionData.ReconfigureComputeResource_Task($spec, $true)
    $task1 = Get-Task -Id ("Task-$($task.value)")
    $waitask = $task1 | Wait-Task 
}

function New-VMBackup
{
    <#
    .SYNOPSIS
        Creates a ghettoVCB backup to supplied VM

    .DESCRIPTION
        Takes a VM name, finds the ESXi host the VM resides on and initates a ghettoVCB backup via SSH session to discovered host.
        Requires passing a quiesce type flag and uses this to choose the requireed ghettoVCB configuration file

    .EXAMPLE
        New-VMBackup -vm vmname -quiesce disabled
    #>    

    Param(
    [Parameter(mandatory=$true)]
    [String]$vm,
    [Parameter(mandatory=$true)]
    [String]$quiesce,
    [Parameter(mandatory=$true)]
    [String]$esxiRootPassword
    )

    Try
    {
        $esxiHost = ((Get-VM -name $vm).vmHost).name
        If ($esxiHost)
        {
            If ($quiesce -eq "disabled")
            {
                LogMessage -message "Backup with Quiesce Disabled requested"
                $myCommand = "rm -f ./$($vm)-backup.log; /opt/ghettovcb/bin/ghettoVCB.sh -m $vm -g /vmfs/volumes/$backupLocation/configurations/ghettoVCB-quiesce-disabled.conf -l ./$($vm)-backup.log"    
            }
            elseif ($quiesce -eq "enabled")
            {
                LogMessage -message "Backup with Quiesce Enabled requested"
                $myCommand = "rm -f ./$($vm)-backup.log; /opt/ghettovcb/bin/ghettoVCB.sh -m $vm -g /vmfs/volumes/$backupLocation/configurations/ghettoVCB-quiesce-enabled.conf -l ./$($vm)-backup.log"
            }
            else 
            {
                LogMessage -message "No Quiesce Option specfied. Please rety using the -quiesce option" -colour red
                Write-Host"";Exit
            }
            LogMessage -message "Creating SSH Session to $esxiHost"

            #create ssh session
            $defaultAdministrator = "root"
            $PlainSafeModeAdministratorPassword = $esxiRootPassword
            $SecureSafeModeAdministratorPassword = ConvertTo-SecureString -String $PlainSafeModeAdministratorPassword -AsPlainText -Force
            $myCreds = New-Object System.Management.Automation.PSCredential ($defaultAdministrator, $SecureSafeModeAdministratorPassword)
            $session = New-SshSession -ComputerName $esxiHost -credential $myCreds -AcceptKey -errorAction SilentlyContinue
            
            If ($session)
            {
                #start backup
                LogMessage -message "Initating Backup of $vm on $esxiHost" -colour yellow
                $result = Invoke-SshCommand -timeout 7200 -session $session.sessionid -command $myCommand
                LogMessage -message "Backup finished. Checking Result."
                If ($result.output -like "*###### Final status: All VMs backed up OK! ######*")
                {
                    LogMessage -message "Log reports successful backup of $vm"
                }
                else
                {
                    LogMessage -message "Please check log as log reports that backup did not successfully complete for $vm" -colour Red    
                }
                LogMessage -message "Adding output to log file $logFile"
                $result.output | Out-File $logFile -encoding ASCII -append
                Get-SSHSession | Remove-SSHSession | Out-Null                
            }
            else 
            {
                LogMessage -message "Failed to create SSH Session to $esxiHost" -colour red    
            }
        }
        else
        {
            LogMessage -message "Unable to find a ESXi Host for $vm" -colour red
        }
            
    }
    Catch
    {
        catchWriter -object $_
    }
}

Function New-VMRestore
{
    <#
    .SYNOPSIS
        Restores a ghettoVCB backup of supplied VM

    .DESCRIPTION
        Takes a VM name, and target ESXi host FQDN, locates the backup on the backup location and initiates the restore via ghettoVCB.

    .EXAMPLE
        New-VMBackup -vm vmname -quiesce disabled
    #>    

    Param(
    [Parameter(mandatory=$true)]
    [String]$vm,
    [Parameter(mandatory=$true)]
    [String]$esxiHost,
    [Parameter(mandatory=$true)]
    [String]$esxiRootPassword
    )
    Try
    {   
        LogMessage -message "Creating SSH Session to $esxiHost"

        #create ssh session
        $defaultAdministrator = "root"
        $PlainSafeModeAdministratorPassword = $esxiRootPassword
        $SecureSafeModeAdministratorPassword = ConvertTo-SecureString -String $PlainSafeModeAdministratorPassword -AsPlainText -Force
        $myCreds = New-Object System.Management.Automation.PSCredential ($defaultAdministrator, $SecureSafeModeAdministratorPassword)
        $session = New-SshSession -ComputerName $esxiHost -credential $myCreds -AcceptKey -errorAction SilentlyContinue
        
        If ($session)
        {
            #restore backup
            $findBackupCommand = "ls /vmfs/volumes/$backupLocation/$vm"
            LogMessage -message "Finding Backup for $vm"
            $output = Invoke-SshCommand -session $session.sessionid -command $findBackupCommand
            $backupImage = $output.output
            If ($backupImage)
            {
                LogMessage -message "Backup Found: $backupImage"
                $createRestoreFile = "rm -f ./$vm.rf; echo `'`"/vmfs/volumes/$backupLocation/$vm/$backupImage;/vmfs/volumes/$targetDatastore;3`"`' >$vm.rf"
                LogMessage -message "Creating Restore File for $vm"
                $createdFile = Invoke-SshCommand -session $session.sessionid -command $createRestoreFile
                $restoreCommand = "/opt/ghettovcb/bin/ghettoVCB-restore.sh -c $vm.rf"
                LogMessage -message "Initating Restore Process for $vm from backup $backupImage"
                $result = Invoke-SshCommand -timeout 7200 -session $session.sessionid -command $restoreCommand
                LogMessage -message "Restore complete. Checking Result."
                If ($result.output -like "*################## Completed restore for $vm`! #####################*")
                {
                    LogMessage -message "Log reports successful restore of $vm"
                }
                else
                {
                    LogMessage -message "Please check log as log reports that restore of $vm did not successfully complete" -colour Red    
                }
                LogMessage -message "Adding output to log file $logFile"

                $result.output | Out-File $logFile -encoding ASCII -append
                Get-SSHSession | Remove-SSHSession | Out-Null
            }
            else 
            {
                LogMessage -message "No backup was found for $vm" -colour red
                Write-Host "";Exit   
            }
        }
        else 
        {
            LogMessage -message "Failed to create SSH Session to $esxiHost" -colour red
            Exit
        }
    }
    Catch
    {
        catchWriter -object $_
    }
}

#Execution


Clear


Write-Host " ";Write-Host " ghettoVCB Wrapper Utility" -foregroundcolor cyan
Write-Host " **************************" -foregroundcolor cyan
Write-Host " "

If ($backup -AND $restore)
{
    LogMessage -message "You cannot specify both the -backup and the -restore options simultaneously. Please select just one" -colour red
    Write-Host"";Exit
}
If ($backup)
{
    If ($quiesce)
    {
        $vmToBackup = Get-VM -name $vm -errorAction SilentlyContinue
        If ($vmToBackup)
        {
            Get-VMSettings -vm $vmToBackup
            New-VMBackup -vm $vm -quiesce $quiesce -esxiRootPassword $esxiRootPassword
        }
        else 
        {
            LogMessage -message "Could not locate the requested VM name. Please confirm and try again" -colour red
            Write-Host "";Exit
        }        
    }
    else
    {
        LogMessage -message "You must supply the -quiesce option with desired value" -colour red
        Write-Host "";Exit
    }
}
elseif ($restore)
{

    If (!$ovfonly)
    {
        If ($esxiHost)
        {
            New-VMRestore -vm $vm -esxiHost $esxiHost -esxiRootPassword $esxiRootPassword
        }
        else 
        {
            LogMessage -message "You requested a restore but ommited the target ESXi Host. Please try again using the -esxihost paramter to specify" -colour red
        }
    }
    $restoredVM = Get-VM -name $vm -errorAction SilentlyContinue 
    If (!$restoredVM)
    {
        Do
        {
            Sleep 1
            $restoredVM = Get-VM -name $vm -errorAction SilentlyContinue
        }
        Until ($restoredVM -OR ($counter -eq 10))
    }
    If ($restoredVM)
    {
        $settingsBackupExists = Test-Path -path "$($restoredVM.name)-settings-backup.json"
        If ($settingsBackupExists)
        {
            $vmSettings = Get-content "$($restoredVM.name)-settings-backup.json" | convertfrom-json
            If ($vmSettings.ovfProperties)
            {
                Set-VMOvfIPAssignment -vm $restoredVM -assignment $vmSettings.ovfProperties.IpAssignment
                If ($vmSettings.ovfProperties.eula)
                {
                    Set-VMOvfEULA -vm $restoredVM -eula $vmSettings.ovfProperties.eula    
                }
                Set-VMOvfEnvTransport -vm $restoredVM -transport $vmSettings.ovfProperties.ovfEnvironmentTransport
                foreach ($product in $vmSettings.ovfProperties.product)
                {
                    New-VMOvfProduct -vm $restoredVM -product $product
                }
                foreach ($property in $vmSettings.ovfProperties.property)
                {
                    New-VMOvfProperty -vm $restoredVM -property $property
                }                 
            }
            else 
            {
                LogMessage -message "Skipping OVF property restore as no backup data was found for $vm." -colour magenta
            }

            If ($vmSettings.inventoryLocations)
            {
                LogMessage -message "Restoring $($restoredVM.name) to folder location `"$($vmSettings.inventoryLocations.folder)`""
                Move-VM -vm $restoredVM -InventoryLocation $vmSettings.inventoryLocations.folder | Out-Null
                LogMessage -message "Restoring $($restoredVM.name) to resource pool `"$($vmSettings.inventoryLocations.ResourcePool)`""
                Move-VM -vm $restoredVM -Destination $vmSettings.inventoryLocations.ResourcePool | Out-Null
            }
            else 
            {
                LogMessage -message "Skipping relocation of VM to Folder and Resource Pool as no backup data was found for $vm." -colour magenta
            }

            If ($vmSettings.drsSettings)
            {
                $retrievedCluster = (Get-VMHost -name $($restoredVM.VMHost.name)).parent.name
                Foreach ($group in $vmSettings.drsSettings.groups)
                {
                    $discoveredDrsGroup = Get-DrsClusterGroup -name $group.groupname
                    If (($discoveredDrsGroup.member).count -eq 0)
                    {
                        LogMessage -message "Adding VM to empty (currently invalid) DRS Group `"$($group.groupname)`""
                        Add-VMtoEmptyDRSGroup -cluster $retrievedCluster -group $group.groupname -vm $restoredVM
                    }
                    else 
                    {
                        LogMessage -message "Adding $($restoredVM.name) to DRS Group `"$($group.groupname)`""                
                        Set-DrsClusterGroup -drsclustergroup $discoveredDrsGroup -VM $restoredVM  -Add | Out-Null    
                    }
                }
                
                Foreach ($rule in $vmSettings.drsSettings.rules)
                {            
                    $vmNames = $rule.vmnames.split(",")
                    $vms = foreach ($name in $vmNames){get-vm -name $name -errorAction SilentlyContinue}
                    If ($vms.count -eq $vmNames.count)
                    {
                        $drsRule = Get-DrsRule -Cluster $retrievedCluster -name $rule.name -errorAction SilentlyContinue
                        If ($drsRule) 
                        {
                            LogMessage -message "Tearing down DRS Rule $($rule.name)"
                            Remove-DrsRule $drsRule -confirm:$false| Out-Null
                        }
                        LogMessage -message "Recreating DRS Rule `"$($rule.name)`"   including restored VM $($restoredVM.name)"
                        New-DrsRule -cluster $retrievedCluster -name $rule.name -VM $vms -keepTogether $rule.keepTogether -Enabled $true | Out-Null
                    }
                    else 
                    {
                        LogMessage -message "Not altering DRS Rule configuration as not all member VMs were discovered in vCenter inventory"    
                    }
                }
            }
            else 
            {
                LogMessage -message "Skipping resetting of DRS Groups and Rules as no backup data was found for $vm." -colour magenta
            }
        }
        else 
        {
            LogMessage -message "Could not find backup file $($restoredVM.name)-settings-backup.json to restore additional settings" -colour red    
        }       
    }
    else 
    {
        LogMessage -message "Something went wrong. Could not find the resored VM $vm." -colour red
    }
}
else 
{
    LogMessage -message "You did not specify an operation type. Please try again using one of the -backup or -restore options" -colour red
}