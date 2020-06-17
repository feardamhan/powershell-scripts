# Script to Manage Cloud Management Platform (CMP) Environment
# Created by Ken Gould (Dell EMC)
# Provided with zero warranty! Please test before using in anger!
# Version 15
# DO NOT USE THIS SCRIPT WITH OUT CHANGING THE $vAppName PARAMTER TO YOUR VAPP !!!!

## CHANGELOG ##
# v15
#       Re-ordered start menu to accurately reflect the correct sequence of startup operations
#       Added function to validate presence of DC01 snapshot at start-p and suggest taking one if not present
# v14
#		Fixed bug where credential files were unusable after shutdown or fresh deployment of vApp by specifying the key to be used for encryption and decryption
# v13
# 		Added graceful shutdown of DPA
# 		Added graceful shutdown of AVE Systems
#		Added vAppName detection and validation
# v12
#		Added snapshot functionality of DC01 at vCD vApp layer
################################################# USER PARAMETERS ######################################################

#Do not use this script with out changing the $vAppname paramter to your vApp
$vAppName = "ChangeMe"

#Infrastructure Paramters
$vcenter_fqdn = "vc01.domain.local"
$vcenter_user = "administrator@vsphere.local"
$vcenter_password = "VMwar3!!"
$lab_vcenter = "drmlab-vc01.infra.lab.local"
$lab_ci ="10.103.244.121"
$lab_username = "lab\administrator"
$ci_username = "Administrator"
$ave_username = "admin"
$ave_password = "VMwar3_"

# To change the user, alter the user in $lab_username or $ci_username and create a new credentials file using the following syntax (providing the filename you wish to store it in)
# Note the 'key' parameter is important to ensure decryption works.
# Read-Host -AsSecureString | ConvertFrom-SecureString -key (3,4,2,3,56,34,254,222,1,1,2,23,42,54,33,233,1,34,2,7,6,5,35,43) | Out-File c:\scripts\lab_password.txt
# Read-Host -AsSecureString | ConvertFrom-SecureString -key (3,4,2,3,56,34,254,222,1,1,2,23,42,54,33,233,1,34,2,7,6,5,35,43) | Out-File c:\scripts\ci_password.txt
# Provide the correspeonding password and at the prompt at hit enter. Enter the filename in the relevant $lab_password_file or $ci_password_file variable
$lab_password_file = "c:\scripts\lab_password.txt"
$ci_password_file = "c:\scripts\ci_password.txt"

#Cluster Startup/Shutdown Parameters
$cluster = "MARVIN-Virtual-SAN-cluster"
$VC01_platform_vms = @("PSC01", "VC01")
$VC01_cluster_hosts = @("esxi04.domain.local", "esxi05.domain.local", "esxi06.domain.local", "esxi07.domain.local")
$VC01_primary_host = "esxi04.domain.local"
$esxi_user = "root"
$esxi_password = "VMwar3!!"
$VC02_platform_vms = @("VC02")
$VC02_cluster_hosts = @("esxi01.domain.local", "esxi02.domain.local", "esxi03.domain.local", "esxi08.domain.local")
$VC02_primary_host = "esxi01.domain.local"
$ave_systems = @("ave-01.domain.local")

#Stack PowerUp/PowerDown Paramters
$phase_1_vrs_stack_VMs = @("nsx-mgr01", "AutoPOD_LB-0", "AutoPOD_LB-1")
$phase_2_vrs_stack_VMs = @("autosql", "vra01")
$phase_3_vrs_stack_VMs = @("vra02","avp-01.domain.local")
$phase_4_vrs_stack_VMs = @("web01", "web02")
$phase_5_vrs_stack_VMs = @("mgr01", "mgr02")
$phase_6_vrs_stack_VMs = @("dem01", "dem02")
$phase_7_vrs_stack_VMs = @("agt01", "agt02")

#Snapshot Parameters
$snapshot_vm_list = @("dpa01","cloudlink","vra01", "vra02", "web01", "web02", "mgr01", "mgr02", "dem01", "dem02", "agt01", "agt02", "autosql")
$snapshot_name = "PoweredOffStack"

# Define DRS Levels to stop VMs from moving away from the defined host
$PartiallyAutomated = "PartiallyAutomated"
$FullyAutomated = "FullyAutomated"

# Extension Components
$secondary_components = @("dpa01","cloudlink")

###################################### DO NOT MODIFY ANYTHING BELOW THIS LINE ############################################

$version = "15"

# Enable communication with VMCA signed vCenter
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12;

# Add Required PowerCli Modules
Get-Module -ListAvailable VM* | Import-Module
Import-Module VMware.VimAutomation.Cloud

#get vCD and Lab credentials
$Key = (3,4,2,3,56,34,254,222,1,1,2,23,42,54,33,233,1,34,2,7,6,5,35,43)
$lab_password = get-content $lab_password_file | convertto-securestring -key $key
$ci_password = get-content $ci_password_file | convertto-securestring -key $key
$lab_credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist $lab_username,$lab_password
$ci_credentials = new-object -typename System.Management.Automation.PSCredential -argumentlist $ci_username,$ci_password

Function ConnectVIServer ($VIHost, $User, $Password) {
	Write-Host " Connecting to"$VIHost": " -Foregroundcolor white -nonewline
    Connect-VIServer $VIHost -User $User -Password $Password | Out-Null
	Write-Host "Connected" -Foregroundcolor Green
}

Function DisconnectVIServer ($VIHost) 
{
	Write-Host " Disconnecting from"$VIHost": " -Foregroundcolor white -nonewline
    Disconnect-VIServer $VIHost -confirm:$false | Out-Null
	Write-Host "Disconnected" -Foregroundcolor Green
}

Function ConnectLab 
{
	Write-Host " Connecting to vCD: " -Foregroundcolor white -nonewline
    Connect-VIServer -Server $lab_vcenter -credential $lab_credentials | Out-Null
	Connect-CIServer -Server $lab_ci -credential $ci_credentials | Out-Null
	Write-Host "Connected" -Foregroundcolor Green
}

Function DisconnectLab
{
	Write-Host " Disconnecting from vCD: " -Foregroundcolor white -nonewline
    Disconnect-VIServer $lab_vcenter -confirm:$false | Out-Null
	Disconnect-CIServer $lab_ci -confirm:$false | Out-Null
	Write-Host "Disconnected" -Foregroundcolor Green
}

Function ChangeDRSLevel ($Level) 
{						
    Write-Host " Changing cluster DRS Automation Level to Partially Automated" -Foregroundcolor yellow
    Get-cluster $cluster | Set-cluster -DrsAutomation $Level -confirm:$false | Out-Null
}
						
Function MoveVMs {

    Foreach ($VM in $VC01_platform_vms) {
        Write-Host " Moving $VM to"$VC01_primary_host": " -Foregroundcolor white -nonewline
        Get-VM $VM | Move-VM -Destination $VC01_primary_host -Confirm:$false | Out-Null
        Write-Host "Moved" -Foregroundcolor green
    }   
    Disconnect-VIServer $vcenter_fqdn -confirm:$false | Out-Null
}

# Function to put all ESXi hosts into maintenance mode with the No Action flag for vSAN data rebuilds
Function EnterMaintenanceMode {

    Foreach ($VMHost in $VC01_cluster_hosts) {
        Connect-VIServer $VMHost -User $esxi_user -Password $esxi_password | Out-Null
        Write-Host " Putting $VMHost into Maintenance Mode: " -Foregroundcolor white -nonewline
        Get-View -ViewType HostSystem -Filter @{"Name" = $VMHost }|?{!$_.Runtime.InMaintenanceMode}|%{$_.EnterMaintenanceMode(0, $false, (new-object VMware.Vim.HostMaintenanceSpec -Property @{vsanMode=(new-object VMware.Vim.VsanHostDecommissionMode -Property @{objectAction=[VMware.Vim.VsanHostDecommissionModeObjectAction]::NoAction})}))}
        Write-Host "Done." -Foregroundcolor green
        Disconnect-VIServer $VMHost -confirm:$false | Out-Null		
    }
}

# Function to Exit hosts from maintenance mode
Function ExitMaintenanceMode {

    Foreach ($VMHost in $VC01_cluster_hosts) 
	{
        Connect-VIServer $VMHost -User $esxi_user -Password $esxi_password | Out-Null
        Write-Host " Exiting Maintenance Mode for"$VMHost": " -Foregroundcolor white -nonewline
        Set-VMHost $VMHost -State "Connected" | Out-Null
        Write-Host "Done" -Foregroundcolor green
        Disconnect-VIServer $VMHost -confirm:$false | Out-Null
     }   
    Write-Host " Waiting for vSAN cluster to stabilize" -Foregroundcolor yellow
	sleeper_agent 60
}

# Function to Start VMs in the reverse order they were powered down									
Function StartVMs ($VMs) {
    Foreach ($VM in $VMs) {
        $dots = 0
		Write-Host " Powering on"$VM": " -foregroundcolor white -nonewline 
        Start-VM $VM -Confirm:$false | Out-Null
		do {
			$dots++
			$powerState = (get-vm $VM).PowerState
			if ($dots -eq 40)
			{
				Write-Host "." -Foregroundcolor yellow -nonewline
				$dots = 0
			}
        }
        while ($VM -eq "PoweredOff")
        Write-Host " Done" -Foregroundcolor green	
    }

}

# Function to Shutdown VMs
Function ShutdownVM ($VMs) {
    # Reverse the VM list to start in reverse order
    [array]::Reverse($VMs)
    Foreach ($VM in $VMs) {
        $dots = 0
		Write-Host " Shutting down"$VM" " -Foregroundcolor white -nonewline
        Shutdown-VMGuest $VM -Confirm:$false | Out-Null
        do {
            $dots++
			$powerState = (get-vm $VM).PowerState
			if ($dots -eq 40)
			{
				Write-Host "." -Foregroundcolor yellow -nonewline
				$dots = 0
			}
        }
        while ($powerState -eq "PoweredOn")
        Write-Host " Done" -Foregroundcolor green	
    }
}

# Function to shutdown hosts
Function ShutdownESXiHosts ($hosts_to_shutdown)
{
    Foreach ($VMHost in $hosts_to_shutdown) 
	{
        Write-Host " Shutting down"$VMHost": " -Foregroundcolor white -nonewline
		Connect-VIServer -Server $VMHost -User $esxi_user -Password $esxi_password | %{
            Get-VMHost -Server $_ | %{
                $_.ExtensionData.ShutdownHost_Task($TRUE) | Out-Null
            }
        }
        Write-Host "Shutdown" -Foregroundcolor green
		Disconnect-VIServer -Server $VMHost -confirm:$false
    }
}

# Function to Poll the status of vCenter after starting up the VM
Function PollvCenter {
    $vcenter_poll_attempts = 0
    Write-Host " Polling vCenter $vcenter_fqdn (this will potentially take in excess of 60 attempts)" -foregroundcolor yellow
	do
    {
        try 
        {
            $vcenter_poll_attempts++
			# Create Web Request
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
            $HTTP_Request = [System.Net.WebRequest]::Create("https://$($vcenter_fqdn):9443")

            # Get a response
            $HTTP_Response = $HTTP_Request.GetResponse()

            # Get the HTTP code
            $HTTP_Status = [int]$HTTP_Response.StatusCode
            
            If ($HTTP_Status -eq 200) 
			{ 
                Write-Host "`r Attempt #"$vcenter_poll_attempts": " -ForegroundColor white -nonewline
				Write-Host "Available  "  -ForegroundColor Green
                # Close HTTP request
                $HTTP_Response.Close()
            }
        }
        catch { 
            Write-Host "`r Attempt #"$vcenter_poll_attempts": " -ForegroundColor white -nonewline
			Write-Host "Unavailable"  -ForegroundColor yellow -nonewline
            sleep 5
    } }
    While ($HTTP_Status -ne 200)	
}

Function ListDCSnapshot
{
	ConnectLab
	$vapp = Get-CIVApp -Name $vAppName
	$vm = $vapp.extensiondata.Children.vm | where {$_.Name -Match "DC01"} | Get-View | Select-Object -ExpandProperty Name
	Write-Host " Snapshots discovered on"$vm": " -ForegroundColor white -nonewline
		$vm_snapshots_obj = get-vm -name $vm | Get-Snapshot | select -ExpandProperty Name
		$vm_snapshots = [string]$vm_snapshots_obj
		If ($vm_snapshots)
		{
			Write-host "$vm_snapshots" -foregroundcolor yellow
		}
		else
		{
			Write-host "None found" -foregroundcolor yellow
		}
	DisconnectLab
}

Function ValidateDCSnapshot
{
    $vapp = Get-CIVApp -Name $vAppName
    $vm = $vapp.extensiondata.Children.vm | where {$_.Name -Match "DC01"} | Get-View | Select-Object -ExpandProperty Name
    $vm_snapshots_obj = get-vm -name $vm | Get-Snapshot | select -ExpandProperty Name
        $vm_snapshots = [string]$vm_snapshots_obj
        If (!$vm_snapshots)
        {
            Write-host " No snapshot found on DC01, please use relevant menu option to create one before proceeding" -foregroundcolor cyan
            anyKey
        }
        else 
        {
            Write-host " Snapshot found on DC01. Proceeding." -foregroundcolor green
            sleeper_agent 1   
        }
}

Function CreateDCSnapshot
{
	ConnectLab
	$vapp = Get-CIVApp -Name $vAppName
	$vm = $vapp.extensiondata.Children.vm | where {$_.Name -Match "DC01"} | Get-View | Select-Object -ExpandProperty Name
	get-vm -Name $vm | New-Snapshot -Name $snapshot_name -Memory -quiesce -WarningAction silentlyContinue | Out-Null
	DisconnectLab
}

Function RevertDCSnapshot
{
	ConnectLab
	$vapp = Get-CIVApp -Name $vAppName
	$vm = $vapp.extensiondata.Children.vm | where {$_.Name -Match "DC01"} | Get-View | Select-Object -ExpandProperty Name
	$snap = Get-Snapshot -VM $vm | Sort-Object -Property Created -Descending | Select -First 1
	Set-VM -VM $vm -SnapShot $snap -Confirm:$false | Out-Null
	DisconnectLab
}

Function ListSnapshots
{
	Foreach ($VM in $snapshot_vm_list)
	{
		Write-Host " Snapshots discovered on"$VM": " -ForegroundColor white -nonewline
		$vm_snapshots_obj = get-vm -name $VM | Get-Snapshot | select -ExpandProperty Name
		$vm_snapshots = [string]$vm_snapshots_obj
		If ($vm_snapshots)
		{
			Write-host "$vm_snapshots" -foregroundcolor yellow
		}
		else
		{
			Write-host "None found" -foregroundcolor yellow
		}
	}
}

Function CreateVMSnapshot 
{
	Foreach ($VM in $snapshot_vm_list) 
		{
		Write-Host " Creating Snapshot for"$VM": " -foregroundcolor white -nonewline
		New-Snapshot -VM $VM -Memory -quiesce -Name $snapshot_name -RunAsync -WarningAction silentlyContinue | Out-Null
		Write-Host "Done" -foregroundcolor green
		}
}
			
Function RevertVMSnapshot 
{
	Foreach ($VM in $snapshot_vm_list) 
	{
		Write-Host " Reverting Snapshot for"$VM": " -ForegroundColor white -nonewline
		$snap = Get-Snapshot -VM $VM | Sort-Object -Property Created -Descending | Select -First 1
		Set-VM -VM $VM -SnapShot $snap -Confirm:$false | Out-Null
		Write-Host "Done" -ForegroundColor green
	}							 
}

Function DeleteAllNestedSnapshots
{
	Foreach ($VM in $snapshot_vm_list)
	{
	Write-Host " Deleting snapshots discovered on"$VM": " -ForegroundColor white -nonewline
	get-vm -name $VM | Get-Snapshot | Remove-Snapshot -RunAsync -confirm:$false | out-null
	Write-Host "Done" -ForegroundColor green
	}
}

Function anyKey 
{
    Write-Host ""
	Write-Host -NoNewline -Object ' Press any key to return to the main menu...' -ForegroundColor yellow
    $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    Menu
}

Function StopDPA ($VM)
{
	Write-Host " Stopping DPA on $VM. Please be patient" -foregroundcolor yellow
	Invoke-Command -computername $VM -ScriptBlock {dpa service stop} -ErrorVariable errmsg 2>$null | out-null
	Write-Host " Validating state of EMC DPA Agent Service: " -nonewline
	Do
	{
		$service1 = Get-Service -computername $VM -name "EMC DPA Agent Service"
	}
	Until ($service1.status -eq "Stopped")
	Write-Host "Stopped" -foregroundcolor green
	Write-Host " Validating state of EMC DPA Application Service: " -nonewline
	Do
	{
		$service2 = Get-Service -computername $VM -name "EMC DPA Application Service"
	}
	Until ($service2.status -eq "Stopped")
	Write-Host "Stopped" -foregroundcolor green
	Write-Host " Validating state of EMC DPA Datastore Service: " -nonewline
	Do
	{
		$service3 = Get-Service -computername $VM -name "EMC DPA Datastore Service"
	}
	Until ($service3.status -eq "Stopped")
	Write-Host "Stopped" -foregroundcolor green
}

Function StopAVE ($ave_list)
{
	Foreach ($ave in $ave_list)
	{
		Write-Host " Stopping $ave gracefully. Please be patient"
		$plinkCommand = "c:\scripts\plink.exe -ssh -l $ave_username -pw $ave_password $ave dpnctl stop"
		cmd.exe /c $plinkCommand | out-null
		Write-Host " $ave stopped" -foregroundcolor green
		Write-Host " Powering off $ave"
		$shutdown_string = "echo $ave_password | sudo -u root -S poweroff"
		$plinkCommand = "c:\scripts\plink.exe -ssh -l $ave_username -pw $ave_password $ave `"$shutdown_string`""
		cmd.exe /c $plinkCommand | out-null
		Write-Host " $ave powered off" -foregroundcolor green
	}
}

Function sleeper_agent ($seconds)
{
	$counter = $seconds
	While ($counter -ge 0) 
	{
		Write-host "`r $counter seconds remaining " -NoNewLine -ForegroundColor white
		Start-Sleep -Seconds 1
		$Counter--
	}
	Write-Host "Finished waiting" -foregroundcolor green
}

# Function to display the main menu 
Function Menu 
{
    Clear-Host         
    Do
    {
        Clear-Host                                                                        
        Write-Host -Object ''
		Write-Host -Object " Manage VRS Version $version (Please choose an option):" -Foregroundcolor Yellow
        Write-Host -Object ' ************************************************' -Foregroundcolor Yellow
        Write-Host -Object ' StartUp Sequence:' -Foregroundcolor cyan
        Write-Host -Object ''	
        Write-Host -Object ' A.  Create DC01 Snapshot (enable full reset of environment) '
        Write-Host -Object ''
        Write-Host -Object ' B.  Start VC01 vSAN cluster & PSC/vCenter '
        Write-Host -Object ''
		Write-Host -Object ' C.  Start All Primary VRS Stack VMs '
        Write-Host -Object ''
        Write-Host -Object ' D.  Start DPA and Cloudlink '
        Write-Host -Object ''
        Write-Host -Object ' Shutdown Sequence:' -Foregroundcolor cyan
		Write-Host -Object ''
        Write-Host -Object ' E.  Shutdown VC02 Hosts (and vCenter) '
        Write-Host -Object ''
		Write-Host -Object ' F.  Shutdown DPA (gracefully) and Cloudlink (only required if they are started) '
        Write-Host -Object ''
		Write-Host -Object ' G.  Shutdown All Primary VRS Stack VMs '
        Write-Host -Object ''
		Write-Host -Object ' H.  Shutdown VC01 vSAN cluster & PSC/vCenter '
		Write-Host -Object ''
		Write-Host -Object ' I.  Shutdown AVE(s) gracefully. Required to avoid AVE corruption '
        Write-Host -Object ''
		Write-Host -Object ' vApp Snapshot Operations:' -Foregroundcolor cyan
		Write-Host -Object ''
		Write-Host -Object ' J.  List DC01 Snapshots '
        Write-Host -Object ''
		Write-Host -Object ' K.  Revert DC01 Snapshot (aligns trust relationship with nested windwows VMs snapshots) '
        Write-Host -Object ''
		Write-Host -Object ' Nested Snapshot Operations:' -Foregroundcolor cyan
		Write-Host -Object ''
		Write-Host -Object ' L.  List Snapshots on Nested VMs '
        Write-Host -Object ''
        Write-Host -Object ' M.  Create Snapshots of Nested VMs (Includes memory if Powered On)'
		Write-Host -Object ''
        Write-Host -Object ' N.  Revert Nested Snapshots ' -nonewline
		Write-Host -Object 'WITHOUT '-foregroundcolor red -nonewline
		Write-Host -Object 'Primary VRS VM Power Up (Powered On Snapshots Only) '
        Write-Host -Object ''
        Write-Host -Object ' O.  Revert Nested Snapshots ' -nonewline
		Write-Host -Object 'WITH '-foregroundcolor green -nonewline
		Write-Host -Object 'Primary VRS VM Power Up (Powered Off Snapshots Only) '
		Write-Host -Object ''
		Write-Host -Object ' P.  Delete ' -nonewline
		Write-Host -Object 'ALL '-foregroundcolor red -nonewline 
		Write-Host -Object 'Nested Snapshots '
		Write-Host -Object ''
		Write-Host -Object ' Other Operations:' -Foregroundcolor cyan
        Write-Host -Object ''
        Write-Host -Object ' X.  Exit'
        Write-Host -Object $errout
        $Menu = Read-Host -Prompt ' (Enter A - P, or X to Exit)'

        switch ($Menu) 
        {
            A
            {
                Write-Host ''
                Write-Host " Creating Snapshot of DC01" -Foregroundcolor yellow
                Write-Host " **************************" -Foregroundcolor yellow
                CreateDCSnapshot
                anyKey
            }
            B 
            { 
				Write-Host ''
				Write-Host " Starting VC01 Hosts and Platform VMs" -Foregroundcolor yellow
				Write-Host " **************************************" -Foregroundcolor yellow
				ExitMaintenanceMode
                ConnectVIServer $VC01_primary_host $esxi_user $esxi_password
                StartVMs $VC01_platform_vms
				PollvCenter
				DisconnectVIServer $VC01_primary_host
				anyKey
            }
			C 
            { 
                Write-Host ''
				Write-Host " Starting VRS VMs" -Foregroundcolor yellow
				Write-Host " *****************" -Foregroundcolor yellow
				ConnectVIServer $vcenter_fqdn $vcenter_user $vcenter_password
                StartVMs $phase_1_vrs_stack_VMs
				Write-Host " Stabilizing VMs: $phase_1_vrs_stack_VMs" -foregroundcolor yellow
				sleeper_agent 60
				StartVMs $phase_2_vrs_stack_VMs
				Write-Host " Stabilizing VMs: $phase_2_vrs_stack_VMs" -foregroundcolor yellow
				sleeper_agent 300
				StartVMs $phase_3_vrs_stack_VMs
                Write-Host " Stabilizing VMs: $phase_3_vrs_stack_VMs" -foregroundcolor yellow
                sleeper_agent 300
                StartVMs $phase_4_vrs_stack_VMs
                Write-Host " Stabilizing VMs: $phase_4_vrs_stack_VMs" -foregroundcolor yellow
                sleeper_agent 60
                StartVMs $phase_5_vrs_stack_VMs
                Write-Host " Stabilizing VMs: $phase_5_vrs_stack_VMs" -foregroundcolor yellow
                sleeper_agent 60
                StartVMs $phase_6_vrs_stack_VMs
                Write-Host " Stabilizing VMs: $phase_6_vrs_stack_VMs" -foregroundcolor yellow
                sleeper_agent 60
                StartVMs $phase_7_vrs_stack_VMs
                DisconnectVIServer $vcenter_fqdn
                Write-Host " All VMs powered on. System will take some time to settle" -foregroundcolor cyan
                Write-Host " Check Registration state of Services on VRA appliances and Syncronization State of vRO cluster nodes before use" -foregroundcolor cyan
				anyKey
            }
			D
            {
                Write-Host ''
                Write-Host " Starting Cloudlink and DPA" -Foregroundcolor yellow
                Write-Host " ***************************" -Foregroundcolor yellow
                ConnectVIServer $vcenter_fqdn $vcenter_user $vcenter_password
				StartVMs $secondary_components
				DisconnectVIServer $vcenter_fqdn
                anyKey
            }
			E 
            {
                Write-Host ''
                Write-Host " Shutting down VC02 and Hosts" -Foregroundcolor yellow
                Write-Host " ******************************" -Foregroundcolor yellow
                ShutdownESXiHosts $VC02_cluster_hosts
                anyKey
            }
			F 
            {
                Write-Host ''
				Write-Host " Shutting down Secondary Components" -Foregroundcolor yellow
				Write-Host " ***********************************" -Foregroundcolor yellow
				StopDPA DPA01
				ConnectVIServer $vcenter_fqdn $vcenter_user $vcenter_password
				ShutdownVM $secondary_components
                DisconnectVIServer $vcenter_fqdn
				anyKey
            }
			G 
            {
				Write-Host ''
				Write-Host " Shutting Down Primary VRS VMs" -Foregroundcolor yellow
				Write-Host " ******************************" -Foregroundcolor yellow
				ConnectVIServer $vcenter_fqdn $vcenter_user $vcenter_password
				ShutdownVM $phase_7_vrs_stack_VMs
				ShutdownVM $phase_6_vrs_stack_VMs
				ShutdownVM $phase_5_vrs_stack_VMs
                ShutdownVM $phase_4_vrs_stack_VMs
                ShutdownVM $phase_3_vrs_stack_VMs
                ShutdownVM $phase_2_vrs_stack_VMs
                ShutdownVM $phase_1_vrs_stack_VMs
				DisconnectVIServer $vcenter_fqdn
				anyKey				
            }
            H
            {
                Write-Host ''
				Write-Host " Shutting down VC01 Platform VMs and Hosts" -Foregroundcolor yellow
				Write-Host " *******************************************" -Foregroundcolor yellow
				ConnectVIServer $VC01_primary_host $esxi_user $esxi_password
                ShutdownVM $VC01_platform_vms
                DisconnectVIServer $VC01_primary_host
				EnterMaintenanceMode
				ShutdownESXiHosts $VC01_cluster_hosts
				anyKey
            }
			I 
            {
                Write-Host ''
				Write-Host " Shutting down AVE Systems" -Foregroundcolor yellow
				Write-Host " **************************" -Foregroundcolor yellow
				StopAVE $ave_systems
				anyKey
            }
			J
            {
                Write-Host ''
                Write-Host " Listing DC01 Snapshots" -Foregroundcolor yellow
                Write-Host " ***********************" -Foregroundcolor yellow
                ListDCSnapshot
                anyKey
            }
			K
			{
				Write-Host ''
                Write-Host " Reverting Snapshot of DC01" -Foregroundcolor yellow
                Write-Host " ***************************" -Foregroundcolor yellow
				RevertDCSnapshot
				anyKey
			}
			L
            {
                Write-Host ''
                Write-Host " Listing Nested Snapshots" -Foregroundcolor yellow
                Write-Host " *************************" -Foregroundcolor yellow
                ConnectVIServer $vcenter_fqdn $vcenter_user $vcenter_password
                ListSnapshots
                DisconnectVIServer $vcenter_fqdn
                anyKey
            }
			M
            {
                Write-Host ''
				Write-Host " Creating Nested Snapshots" -Foregroundcolor yellow
				Write-Host " **************************" -Foregroundcolor yellow
				ConnectVIServer $vcenter_fqdn $vcenter_user $vcenter_password
				CreateVMSnapshot 
				DisconnectVIServer $vcenter_fqdn				
                anyKey
            }
            N
            {
                Write-Host ''
                Write-Host " Reverting Powered On Nested Snapshots" -Foregroundcolor yellow
                Write-Host " **************************************" -Foregroundcolor yellow
                ConnectVIServer $vcenter_fqdn $vcenter_user $vcenter_password
                RevertVMSnapshot
                DisconnectVIServer $vcenter_fqdn
                anyKey
            }
            O
            {
                Write-Host ''
				Write-Host " Reverting Powered Off Nested Snapshots and Powering Up" -Foregroundcolor yellow
				Write-Host " *******************************************************" -Foregroundcolor yellow
				ConnectVIServer $vcenter_fqdn $vcenter_user $vcenter_password
				RevertVMSnapshot
				StartVMs $phase_2_vrs_stack_VMs
				Write-Host " Stabilizing VMs: $phase_2_vrs_stack_VMs" -foregroundcolor yellow
				sleeper_agent 300
				StartVMs $phase_3_vrs_stack_VMs
                Write-Host " Stabilizing VMs: $phase_3_vrs_stack_VMs" -foregroundcolor yellow
                sleeper_agent 300
                StartVMs $phase_4_vrs_stack_VMs
                Write-Host " Stabilizing VMs: $phase_4_vrs_stack_VMs" -foregroundcolor yellow
                sleeper_agent 60
                StartVMs $phase_5_vrs_stack_VMs
                Write-Host " Stabilizing VMs: $phase_5_vrs_stack_VMs" -foregroundcolor yellow
                sleeper_agent 60
                StartVMs $phase_6_vrs_stack_VMs
                Write-Host " Stabilizing VMs: $phase_6_vrs_stack_VMs" -foregroundcolor yellow
                sleeper_agent 60
                StartVMs $phase_7_vrs_stack_VMs
                DisconnectVIServer $vcenter_fqdn
                Write-Host " All VMs powered on. System will take some time to settle" -foregroundcolor cyan
                Write-Host " Check Registration state of Services on VRA appliances and Syncronization State of vRO cluster nodes before use" -foregroundcolor cyan
                anyKey
			}
			P
			{
				Write-Host ''
				Write-Host " Deleting ALL Nested Snapshots" -Foregroundcolor yellow
				Write-Host " ******************************" -Foregroundcolor yellow
				ConnectVIServer $vcenter_fqdn $vcenter_user $vcenter_password
				DeleteAllNestedSnapshots
				DisconnectVIServer $vcenter_fqdn
				anyKey
			}
			X 
            {
                Write-Host " "
				Write-Host " Bon Voyage. It's been emotional." -foregroundcolor cyan
                Write-Host " "
                Exit
            }	
            default 
            {
                $errout = ' Invalid option please try again........Try A-P, or X only'
            }

        }
    }
    until ($Menu -eq 'X')
}   

##### EXECUTE #####

Clear-Host

#check to ensure vAppName is set
If ($vAppName -eq 'ChangeMe')
{
	Write-Host ''
    Write-Host " Unable to Load Script" -foregroundcolor yellow
    Write-Host " **********************" -foregroundcolor yellow
    Write-Host " vAppName not set. Configure the"-foregroundColor cyan -nonewline
    Write-Host " `$vAppName" -foregroundColor yellow -nonewline
    Write-Host " variable in"-foregroundColor cyan -nonewline
    Write-Host " manage_vrs.ps1" -foregroundColor yellow -nonewline
    Write-Host " to match your vCD vApp name before proceeding" -foregroundcolor cyan
    Write-Host ''
	Exit
}
else
{
	#Validate presence of vApp before proceeding to menu
	Write-Host ''
	Write-Host " Detecting vApp" -Foregroundcolor yellow
	Write-Host " ***************" -Foregroundcolor yellow
	ConnectLab
	Write-Host " vApp supplied: " -foregroundcolor white -nonewline
	Write-Host -object "$vAppName" -foregroundcolor yellow
	$vapp = Get-CIVApp -Name $vAppName -erroraction 'silentlyContinue'
	If (!$vapp)
	{
		Write-Host " vApp not found. Please supply a valid vApp name" -foregroundcolor cyan
		DisconnectLab
		Exit
	}
	else
	{	
		Write-Host " vApp found. Proceeding" -foregroundcolor green
        Write-Host " Checking if DC01 has snapshot present" -foregroundcolor white
        ValidateDCSnapshot
        DisconnectLab
		Menu
	}
}