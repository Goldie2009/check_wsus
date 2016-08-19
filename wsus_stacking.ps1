###############################################################################
# Windows PowerShell Skript to get WSUS statistics
# output readable by NRPE for Nagios monitoring
#
# Version 1.1 created 2016-08-18
###############################################################################

# Variables - set these to fit your needs
###############################################################################
# The server name of your WSUS server
$serverName =   # for example 'foobar.foo.bar'

# use SSL connection?
$useSecureConnection =   # $True or $False

# the port number of your WSUS IIS website
$portNumber =   # for example 8531

# warn if a computer has not contacted the server for ... days
$daysBeforeWarn =   # for example 30

# Script - don't change anything below this line!
###############################################################################

# load WSUS framework
[void][reflection.assembly]::LoadWithPartialName("Microsoft.UpdateServices.Administration")   

# connect to specified WSUS server
# see here for information of the IUpdateServer class
# -> http://msdn.microsoft.com/en-us/library/microsoft.updateservices.administration.iupdateserver(VS.85).aspx
$wsus = [Microsoft.UpdateServices.Administration.AdminProxy]::getUpdateServer($serverName, $useSecureConnection, $portNumber)   

# get general status information
# see here for more infos about the properties of GetStatus()
# -> http://msdn.microsoft.com/en-us/library/microsoft.updateservices.administration.updateserverstatus_properties(VS.85).aspx
$status = $wsus.GetStatus()
$totalComputers = $status.ComputerTargetCount

# computers with errors
$computerTargetScope = new-object Microsoft.UpdateServices.Administration.ComputerTargetScope
$computerTargetScope.IncludedInstallationStates = [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::Failed
$computersWithErrors = $wsus.GetComputerTargetCount($computerTargetScope)

# computers with needed updates
$computerTargetScope.IncludedInstallationStates = [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::NotInstalled -bor [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::InstalledPendingReboot -bor [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::Downloaded
$computerTargetScope.ExcludedInstallationStates = [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::Failed
$computersNeedingUpdates = $wsus.GetComputerTargetCount($computerTargetScope)

# computers without status
$computerTargetScope = new-object Microsoft.UpdateServices.Administration.ComputerTargetScope
$computerTargetScope.IncludedInstallationStates = [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::Unknown
$computerTargetScope.ExcludedInstallationStates = [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::Failed -bor [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::NotInstalled -bor [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::InstalledPendingReboot -bor [Microsoft.UpdateServices.Administration.UpdateInstallationStates]::Downloaded
$computersWithoutStatus = $wsus.GetComputerTargetCount($computerTargetScope)

# computers that are OK
$computersOK = $totalComputers - $computersWithErrors - $computersNeedingUpdates - $computersWithoutStatus

# needed, but not approved updates
$updateScope = new-object Microsoft.UpdateServices.Administration.UpdateScope
$updateScope.ApprovedStates = [Microsoft.UpdateServices.Administration.ApprovedStates]::NotApproved
$updateServerStatus = $wsus.GetUpdateStatus($updateScope, $False)
$updatesNeededByComputersNotApproved = $updateServerStatus.UpdatesNeededByComputersCount

# computers that did not contact the server in $daysBeforeWarn days
$timeSpan = new-object TimeSpan($daysBeforeWarn, 0, 0, 0)
$computersNotContacted = $wsus.GetComputersNotContactedSinceCount([DateTime]::UtcNow.Subtract($timeSpan))

# computers in the "not assigned" group
$computerTargetScope = new-object Microsoft.UpdateServices.Administration.ComputerTargetScope
$computersNotAssigned = $wsus.GetComputerTargetGroup([Microsoft.UpdateServices.Administration.ComputerTargetGroupId]::UnassignedComputers).GetComputerTargets().Count

# output and return code
# 0: OK
# 1: WARNING
# 2: CRITICAL
# 3: UNKNOWN
$returnCode = 0
$output = ''
$perfdata = ''
$Warn = 0
$Crit = 0
$help ="Help
wsus_stacking.ps1 <option> <warning(INT)> <critical(INT)>
option  - ComputersNeedingUpdates 	--> Shows count of clients that missing some updates
		- ComputersWithErrors		--> Shows count of clients that have errors while last updating
		- ComputersNotContacted		--> Shows count of clients that haven't contacted since fix days (could only be changed in script)
		- ComputersNotAssigned		--> Shows count of clients that aren't assigned to WSUS
		- UpdatesNeededByComputersNotApproved	--> Shows count of Updates that are needed but aren't approved yet"

if ($args.Length -eq 3 -and $args[1] -is [int] -and $args[2] -is [int]) {
	$Warn = $args[1]
	$Crit = $args[2]
	switch -case ($args[0]) {
		
		"ComputersNeedingUpdates" {
			$output = "$computersNeedingUpdates Client(s) with missing updates."
			if ($computersNeedingUpdates -gt $Warn) {
				$returnCode = 1
				if ($computersNeedingUpdates -gt $Crit) {
					$returnCode = 2
				}
				$output = "$computersNeedingUpdates Client(s) need updates"
			}
			$perfdata = '|' + "'Clients missing updates'=$computersNeedingUpdates;$Warn;$Crit;0;$totalComputers"
		}
		"ComputersWithErrors" {
			$output = "$computersWithErrors Client(s) with errors."
			if ($computersWithErrors -gt $Warn) {
				$returnCode = 1
				if ($computersWithErrors -gt $Crit) {
					$returnCode = 2
				}
				$output = "$computersWithErrors Client(s) with errors"
			}
			$perfdata = '|' + "Clients_with_errors=$computersWithErrors;$Warn;$Crit;0;$totalComputers"
		}
		"ComputersNotContacted" {
			$output = "$computersNotContacted Client(s) haven't contacted WSUS within $daysBeforeWarn days."
			if ($computersNotContacted -gt $Warn) {
				$returnCode = 1
				if ($computersNotContacted -gt $Crit) {
					$returnCode = 2
				}
				$output = "$computersNotContacted Client(s) not contacted within $daysBeforeWarn days"
			}
			$perfdata = '|' + "Clients_not_contacted=$computersNotContacted;$Warn;$Crit;0;$totalComputers"
		}
		"ComputersNotAssigned" {
			$output = "$computersNotAssigned Client(s) not assigned to WSUS."
			if ($computersNotAssigned -gt $Warn) {
				$returnCode = 1
				if ($computersNotAssigned -gt $Crit) {
					$returnCode = 2
				}
				$output = "$computersNotAssigned Client(s) are not assigned to a group"
			}
			$perfdata = '|' + "Clients_not_assigned=$computersNotAssigned;$Warn;$Crit;0;$totalComputers"
		}
		"UpdatesNeededByComputersNotApproved" {
			$output = "$updatesNeededByComputersNotApproved update(s) needed but not approved."
			if ($updatesNeededByComputersNotApproved -gt $Warn) {
				$returnCode = 1
				if ($updatesNeededByComputersNotApproved -gt $Crit) {
					$returnCode = 2
				}
				$output = "$updatesNeededByComputersNotApproved update(s) needed but not approved"
			}
			$perfdata = '|' + "Unapproved_needed_updates=$updatesNeededByComputersNotApproved;$Warn;$Crit;0;$totalComputers"
		}
		default {
			$output = $help
		}
	}
}
else {
	$output = $help
}

$output
$perfdata

exit $returnCode
