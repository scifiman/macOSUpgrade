#!/bin/bash
##########################################################################################
#
#	Copyright (c) 2018 Jamf.  All rights reserved.
#
#		Redistribution and use in source and binary forms, with or without
#		modification, are permitted provided that the following conditions are met:
#		  * Redistributions of source code must retain the above copyright
#			notice, this list of conditions and the following disclaimer.
#		  * Redistributions in binary form must reproduce the above copyright
#			notice, this list of conditions and the following disclaimer in the
#			documentation and/or other materials provided with the distribution.
#		  * Neither the name of the Jamf nor the names of its contributors may be
#			used to endorse or promote products derived from this software without
#			specific prior written permission.
#
#		THIS SOFTWARE IS PROVIDED BY JAMF SOFTWARE, LLC "AS IS" AND ANY
#		EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
#		WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
#		DISCLAIMED. IN NO EVENT SHALL JAMF SOFTWARE, LLC BE LIABLE FOR ANY
#		DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
#		(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#		LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#		ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
#		(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
#		SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
##########################################################################################
#
#	SUPPORT FOR THIS PROGRAM
#		No support is offered
#		The copyright notice is left in place as this was originally written by Jamf.
#
##########################################################################################
#
#	ABOUT THIS PROGRAM
#
#	NAME
#		macOSUpgrade.sh
#
#	SYNOPSIS
#		This script was designed to be used in a Self Service policy to ensure specific
#		requirements have been met before proceeding with an inplace upgrade of the macOS,
#		as well as to address changes Apple has made to the ability to complete macOS
#		upgrades silently.
#
##########################################################################################
#
#	REQUIREMENTS:
#		- Jamf Pro
#		- macOS Clients running version 10.10.5 or later
#		- macOS Installer 10.12.4 or later
#		- eraseInstall option is ONLY supported with macOS Installer 10.13.4+
#			and client-side macOS 10.13+
#		- Look over the USER VARIABLES and configure as needed.
#
#	HISTORY
#
#	Version is: YYYY/MM/DD @ HH:MMam/pm
#	Version is: 2018/10/05 @ 3:45pm
#
#	- 2018/10/05 @ 3:45pm by Jeff Rippy | Tennessee Tech University
#		- Updated to reflect some changes from Joshua's Master Branch, v. 2.7.2.1
#	- 2018/09/28 @ 10:30am by Jeff Rippy | Tennessee Tech University
#		- Updated for macOS 10.14 Mojave
#	- 2018/09/20 @ 3:45pm by Jeff Rippy | Tennessee Tech University
#		- Fixed download loop from going infinite.
#	- 2018/09/18 @ 4:30pm by Jeff Rippy | Tennessee Tech University
#		- Modified for Tennessee Tech
#		- Github source: https://github.com/scifiman/macOSUpgrade
#	- 2018/04/30 by Joshua Roskos | Jamf
#		- Updated
#		- Version v2.6.1
#	- 2018/01/05 by Joshua Roskos | Jamf
#		- Initial Script
#		- Github source: https://github.com/kc9wwh/macOSUpgrade
# 
##########################################################################################
#
#	DEFINE VARIABLES & READ IN PARAMETERS
#
##########################################################################################

# Standard Variables
scriptName="macOSUpgrade"
date="$(date "+%Y%m%d.%H%M.%S")"
appDir="/Applications"
app="${appDir}/app.app"
appVersionFile="${app}/Contents/Info.plist"
caffeinatePID=""
debug="TRUE"
logDir="/tmp/${scriptName}"
log="${logDir}/${scriptName}.log"
mountPoint=""
computerName=""
loggedInUsername=""

# OS Major and Minor version numbers for current OS install.
osMajor="$(/usr/bin/sw_vers -productVersion | awk -F. '{print $2}')"
osMinor="$(/usr/bin/sw_vers -productVersion | awk -F. '{print $3}')"

# Transform GB into Bytes
gigabytes=$((1024 * 1024 * 1024))

# Script specific variables
###downloadTrigger="macOS High Sierra Download"

# eraseInstall is ONLY VALID if the macOS client is 10.13+ and the Installer is 10.13.4+
eraseInstall=0						# 0 = Disabled
									# 1 = Enabled (Factory Default)
eraseOpt=""

# convertToAPFS is ONLY VALID for macOS 10.13 High Sierra installs.  APFS was introduced
# in macOS 10.13 and is optional during the transition.  It is required for
# macOS 10.14 Mojave.
convertToAPFS=1						# 0 = No
									# 1 = Yes
apfsOpt=""

# This positions the dialog box for JamfHelper.
downloadPositionHUD="ur"			# Leave blank for a centered position

userDialog=0						# 0 = Full Screen
									# 1 = Utility Window

# Used to verify the macOS installer download.
validChecksum=0					# 0 = False
									# 1 = True

#################################

# The variables below here are set further in the script.
# They are declared here so they are in the global scope.
downloadTrigger=""
macOSname=""
osInstallerPath=""
installerVersion=""
installerVersionMajor=""
installerVersionMinor=""
osInstallESDChecksum=""

title=""
heading=""
description=""
downloadDescription=""
macOSicon=""
unsuccessfulDownload="FALSE"
requiredMinimumRAM1013=4
requiredMinimumRAM1014=4
requiredMinimumSpace1013=15
requiredMinimumSpace1014=20


minimumRAM1013=$((requiredMinimumRAM1013 * gigabytes))
minimumRAM1014=$((requiredMinimumRAM1014 * gigabytes))
minimumSpace1013=$((requiredMinimumSpace1013 * gigabytes))
minimumSpace1014=$((requiredMinimumSpace1014 * gigabytes))
minimumRAM=""
minimumSpace=""

#################################



##########################################################################################
# 
# SCRIPT CONTENTS - DO NOT MODIFY BELOW THIS LINE
#
##########################################################################################

function finish()
{
	local exitStatus=$1
	[[ $exitStatus ]] || exitStatus=0
	if [[ -n $caffeinatePID ]]; then
		[[ $debug == TRUE ]] && message 0 "Stopping caffeinate PID: $caffeinatePID."
		kill ${caffeinatePID}
	fi
	echo "FINISH: ${log}" | tee -a "${log}"
	logger -f "${log}"
	mv "${log}" "${log}.${date}"
	exit $exitStatus
}

function warningMessage()
{
	local thisCode=$1
	local thisMessage="$2"
	[[ $thisMessage ]] || thisMessage="Unknown Warning"
	echo "WARNING: (${thisCode}) ${thisMessage}" | tee -a "${log}"
}

function normalMessage()
{
	local thisMessage="$1"
	[[ $thisMessage ]] || return
	echo "${thisMessage}" | tee -a "${log}"
}

function errorMessage()
{
	local thisCode=$1
	local thisMessage="$2"
	echo "ERROR: (${thisCode}) ${thisMessage}" | tee -a "${log}"
	finish "$thisCode"
}

function message()
{
	local thisCode=$1
	local thisMessage="$2"

	(( thisCode > 0 )) && errorMessage "$thisCode" "${thisMessage}"
	(( thisCode < 0 )) && warningMessage "$thisCode" "${thisMessage}"
	(( thisCode == 0 )) && normalMessage "${thisMessage}"
}

function downloadInstaller()
{
	# Inform the user about the download.
	message 0 "Downloading $macOSname Installer..."
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
		-windowType hud -windowPosition "$downloadPositionHUD" -title "$title" \
		-alignHeading "center" -alignDescription "left" -description \
		"$downloadDescription" -lockHUD -icon \
		"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarDownloadsFolder.icns" \
		-iconSize 100 &

	# Capture PID for Jamf Helper HUD
	jamfHUDPID=$!
	message 0 "JamfHelper PID is $jamfHUDPID"

	# Run policy to cache installer
	/usr/local/bin/jamf policy -event "$downloadTrigger"

	# Kill jamfHelper HUD post download
	kill "${jamfHUDPID}"
}

function verifyChecksum()
{
	if [[ "$OSInstallESDChecksum" != "" ]]; then
		osChecksum=$( /sbin/md5 -q "$OSInstaller/Contents/SharedSupport/InstallESD.dmg" )
		if [[ "$osChecksum" == "$OSInstallESDChecksum" ]]; then
			message 0 "Checksum: Valid"
			checksumMatch="TRUE"
			return
		else
			checksumMatch="FALSE"
			message 0 "Checksum: Not Valid"
			message 0 "Retrying installer download."
			/bin/rm -rf "$OSInstaller"
			sleep 2
			downloadInstaller
		fi
	else
		return
	fi
}

function createFirstBootScript()
{
	# This creates the First Boot Script to complete the install.
	/bin/mkdir -p /Library/Scripts/tntech/finishOSInstall
	cat << EOF > "/Library/Scripts/tntech/finishOSInstall/finishOSInstall.sh"
#!/bin/bash
# First Run Script to remove the installer.
# Clean up files
/bin/rm -fdr \"$OSInstaller\"
/bin/sleep 2
# Update Device Inventory
/usr/local/bin/jamf recon
# Remove LaunchDaemon
/bin/rm -f /Library/LaunchDaemons/edu.tntech.cleanupOSInstall.plist
# Remove Script
/bin/rm -fdr /Library/Scripts/tntech/finishOSInstall
exit 0
EOF

	/usr/sbin/chown root:admin /Library/Scripts/tntech/finishOSInstall/finishOSInstall.sh
	/bin/chmod 755 /Library/Scripts/tntech/finishOSInstall/finishOSInstall.sh
}

function createLaunchDaemonPlist()
{
	# This creates the plist file for the LaunchDaemon.
	cat << EOF > "/Library/LaunchDaemons/edu.tntech.cleanupOSInstall.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>edu.tntech.cleanupOSInstall</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>-c</string>
		<string>/Library/Scripts/tntech/finishOSInstall/finishOSInstall.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF

	/usr/sbin/chown root:wheel /Library/LaunchDaemons/edu.tntech.cleanupOSInstall.plist
	/bin/chmod 644 /Library/LaunchDaemons/edu.tntech.cleanupOSInstall.plist
}

function createFileVaultLaunchAgentRebootPlist()
{
	# If the drive is encrypted, create this LaunchAgent for authenticated reboots
	# Determine Program Argument
	if (( osMajor >= 11 )); then
		progArgument="osinstallersetupd"
	elif (( osMajor == 10 )); then
		progArgument="osinstallersetupplaind"
	fi

	cat << EOF > "/Library/LaunchAgents/com.apple.install.osinstallersetupd.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>com.apple.install.osinstallersetupd</string>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>MachServices</key>
	<dict>
		<key>com.apple.install.osinstallersetupd</key>
		<true/>
	</dict>
	<key>TimeOut</key>
	<integer>300</integer>
	<key>OnDemand</key>
	<true/>
	<key>ProgramArguments</key>
	<array>
			<string>$OSInstaller/Contents/Frameworks/OSInstallerSetup.framework/Resources/$progArgument</string>
	</array>
</dict>
</plist>
EOF

	/usr/sbin/chown root:wheel /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
	/bin/chmod 644 /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
}

function main()
{
	# For jss scripts, the following is true:
	# Variable $1 is defined as mount point
	# Variable $2 is defined as computer name
	# Variable $3 is defined as username (That is the currently logged in user or root if at the loginwindow.
	# These numbers change from 1-index to 0-index when put in an array.

#	local argArray=()

	# Caffeinate
	/usr/bin/caffeinate -dis &
	caffeinatePID=$!
	[[ $debug == TRUE ]] && message 0 "Disabling sleep during script.  Caffeinate PID is $caffeinatePID."
	jamf recon

#	# Verify arguments are passed in.  Otherwise exit.
#	if [[ "$#" -eq 0 ]]; then
#		message 99 "No parameters passed to script."	# We should never see this.
#	else
#		argArray=( "$@" )
#	fi
#
	# Get the variables passed in and clean up if necessary.
	mountPoint="$1"
	[[ $debug == TRUE ]] && message 0 "Mount Point BEFORE stripping a trailing slash (/) is $mountPoint."
#	unset 'argArray[0]'	# Remove mountPoint from the argArray
	mountPoint="${mountPoint%/}"	# This removes a trailing '/' if present.
	[[ $debug == TRUE ]] && message 0 "Mount Point AFTER stripping a trailing slash (/) is $mountPoint."

	computerName="$2"
	[[ $debug == TRUE ]] && message 0 "Computer name is $computerName."
#	unset 'argArray[1]'	# Remove computerName from the argArray

	loggedInUsername="$3"
	if [[ $loggedInUsername == "" ]]; then
		message 10 "No user currently logged in.  For a macOS install from Self Service, a user MUST be logged in."
	else
		[[ $debug == TRUE ]] && message 0 "Logged in Username is $loggedInUsername."
	fi
#	unset 'argArray[2]'	# Remove loggedInUsername from the argArray

	# Specify full path to OS installer. Use Parameter 4 in the JSS or specify here.
	# Example 1: osInstallerPath="/Applications/Install macOS High Sierra.app"
	# Example 2: osInstallerPath="/Applications/Install macOS Mojave.app"
	osInstallerPath="$4"
	if [[ $osInstallerPath == "" ]]; then
		message 0 "No path to OSInstaller specified.  Acceptable value is \"/Applications/Install macOS <Version Name>.app\""
	else
		[[ $debug == TRUE ]] && message 0 "macOS Installer path is now $osInstallerPath."
	fi
#	unset 'argArray[3]'	# Remove OSInstaller from the argArray

	# Version of OS Installer. Use Parameter 5 in the JSS or specify here.
	# Command to find version: $(/usr/libexec/PlistBuddy -c 'Print :"System Image Info" :version' "/Applications/Install macOS High Sierra.app/Contents/SharedSupprtInstallInfo.plist")
	# Example: 10.13.6

	installerVersion="$5"
	if [[ -n $installerVersion ]]; then
		[[ $debug == TRUE ]] && message 0 "macOS installer version specified as $installerVersion."
	else
		message 20 "No macOS installer version specified. Please input the version of the installer that is being used."
	fi
	installerVersionMajor="$(/bin/echo "$installerVersion" | /usr/bin/awk -F. '{print $2}'"
	installerVersionMinor="$(/bin/echo "$installerVersion" | /usr/bin/awk -F. '{print $3}'"
#	unset 'argArray[4]'	# Remove installerVersion from the argArray

	# downloadTrigger is the custom trigger name of a separate policy used to manage the
	# macOS installer download attempts.  This policy should only have a single package
	# (the macOS installer) and should not have any other scripts or configuration.  The
	# policy should be set to ongoing with no other triggers set and NOT have Self Service
	# enabled.  The only way this policy should execute is by being called using
	# this trigger.  The custom event trigger should match what is passed in to
	# this variable.
	# Set the scope accordingly.  If set up as suggested where the only trigger is
	# initiated from this script, the scope can be set to all computers.
	downloadTrigger="$6"
	if [[ -n $downloadTrigger ]]; then
		[[ $debug == TRUE ]] && message 0 "Specified download trigger is $downloadTrigger."
	else
		message 30 "No download trigger specified."
	fi
#	unset 'argArray[5]'	# Remove downloadTriggerTemp from the argArray

	# MD5 checksum of InstallESD.dmg
	# Optional variable used to compare the downloaded installer and verify as good.
	# This can be blank if you do not want to use this functionality.
	# Example Command: /sbin/md5 "/Applications/Install macOS High Sierra.app/Contents/SharedSupport/InstallESD.dmg"
	# Example: b15b9db3a90f9ae8a9df0f81741efa2b
	osInstallESDChecksum="$7"
	if [[ -n  $osInstallESDChecksum ]]; then
		[[ $debug == TRUE ]] && message 0 "InstallESD checksum specified as $OSInstallESDChecksum."
	else
		message 0 "No InstallESD checksum specified.  It is optional."
		checksumMatch=1
	fi
#	unset 'argArray[6]'	# Remove OSInstallESDChecksum from the argArray



#######################################



	eraseInstallTemp="${argArray[7]}"
	if [[ $eraseInstallTemp == "" ]] || (( eraseInstallTemp == 0 )); then
		message 0 "Erase Install option not specified or 0.  Assuming default of upgrade only.  The erase function will not happen."
	elif (( eraseInstallTemp == 1 )); then
		message 0 "Erase Install has been specified.  This will reset the computer to a \"factory default\" state."
		eraseInstall="$eraseInstallTemp"
	else
		message 100 "Unknown option passed to eraseInstall variable: $eraseInstallTemp.  Exiting."
	fi
	unset 'argArray[7]'	# Remove eraseInstallTemp from the argArray

	convertToAPFSTemp="${argArray[8]}"
	if [[ $convertToAPFSTemp == "" ]] || [[ $convertToAPFSTemp =~ yes ]]; then
		message 0 "Convert to APFS not specified or specified as Yes.  Assuming default action is to convert filesystem to APFS."
	elif [[ $convertToAPFSTemp =~ no ]]; then
		message 0 "Convert to APFS has been specified as No.  Action is to NOT convert filesystem to APFS."
		convertToAPFS="NO"
	else
		message 110 "Unknown option passed to convertToAPFS variable: $convertToAPFSTemp.  Exiting."
	fi
	unset 'argArray[8]'	# Remove convertToAPFSTemp from the argArray

	# Get title of the OS, i.e. macOS High Sierra
	# Use these values for the user dialog box
	macOSname="$(echo "$OSInstaller" | sed 's/^\/Applications\/Install \(.*\)\.app$/\1/')"
	title="$macOSname Upgrade"	# This only applies to Utility Window, not Full Screen.
	heading="Please wait as your computer is prepared for $macOSname..."
	description="This process will take approximately 5-10 minutes. Once completed, your computer will reboot and begin the upgrade process."
	downloadDescription="The installer resources for $macOSname need to download to your computer before the upgrade process can begin.  Please allow this process approximately 30 minutes to complete.  Your download speeds may vary."
	# This positions the dialog box for JamfHelper.
	downloadPositionHUD="ur"	# Leave blank for a centered position
	macOSicon="$OSInstaller/Contents/Resources/InstallAssistant.icns"
	
	# Get Current User
	currentUser="$(stat -f %Su /dev/console)"

	# Check if FileVault Enabled
	fvStatus="$(/usr/bin/fdesetup status | head -1)"

	# Check if device is on battery or ac power
	pwrAdapter="$(/usr/bin/pmset -g ps)"
	if [[ ${pwrAdapter} == *"AC Power"* ]]; then
		pwrStatus="OK"
		message 0 "Power Check: OK - AC Power Detected"
	else
		message 0 "Launching jamfHelper Dialog (Power Requirements Not Met)..."
		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "Power Status Error" -icon "$macOSicon" -heading "AC Adapter Not Plugged In." -description "AC adapter not connected.  Please connect to power before proceeding." -iconSize 100 -button1 "OK" -defaultButton 1 -timeout 300 -countdown
		pwrAdapter="$(/usr/bin/pmset -g ps)"
		if [[ ${pwrAdapter} == *"AC Power"* ]]; then
			pwrStatus="OK"
			message 0 "Power Check: OK - AC Power Detected"		
		else
			pwrStatus="ERROR"
			message 0 "Power Check: ERROR - No AC Power Detected"
		fi
	fi

	# Get current free space available.
	freeSpace=$(diskutil info / | awk -F'[()]' '/Free Space|Available Space/ {print $2}' | sed -e 's/\ Bytes//')
	OSInstallerVersionSED="$(echo "$installerVersion" | awk -F. '{print $1$2}')"
	# Check if free space > 15GB for 10.13 or > 20GB for 10.14
	if [[ $OSInstallerVersionSED -eq "1014" ]]; then
		minimumSpace="$minimumSpace1014"
		#&& "$freeSpace" -ge "$minimumSpace" ]]; then
	elif [[ $OSInstallerVersionSED -eq "1013" ]]; then
		minimumSpace="$minimumSpace1013"
	fi

	if (( freeSpace < minimumSpace )); then
		spaceStatus="ERROR"
		message 0 "Disk Check: ERROR - $freeSpace Free Space Detected.  This is below threshold of $minimumSpace required."
	else
		spaceStatus="OK"
		message 0 "Disk Check: OK - $freeSpace Free Space Detected."
	fi

	# Check amount of RAM installed
	installedRAM="$(/usr/sbin/sysctl -n hw.memsize)"
	if (( installedRAM < minimumRAM )); then
		ramStatus="ERROR"
		message 0 "RAM Check: ERROR - $installedRAM RAM Detected.  This is below threshold of $minimumRAM required."
	else
		ramStatus="OK"
		message 0 "RAM Check: OS - $installedRAM RAM Detected."
	fi

	# Check for existing OS installer
	loopCount=0
	while [[ $loopCount -lt 3 ]]; do
		if [[ -e "$OSInstaller" ]]; then
			message 0 "$OSInstaller found, checking version."
			OSVersion=$(/usr/libexec/PlistBuddy -c 'Print :"System Image Info":version' "$OSInstaller/Contents/SharedSupport/InstallInfo.plist")
			message 0 "OSVersion is $OSVersion"
			if [[ $OSVersion == "$installerVersion" ]]; then
				message 0 "Installer found, version matches. Verifying checksum..."
				verifyChecksum
				if [[ $checksumMatch ]]; then
					message 0 "Installer checksum matches.  Exiting download loop and continuing."
					message 0 "Date stamp: $(date "+%Y%m%d.%H%M.%S")"
					unsuccessfulDownload="FALSE"
					break
				fi
			else
				# Delete old version.
				message 0 "Installer found, but not the specified version. Deleting and downloading a new copy..."
				/bin/rm -rf "$OSInstaller"
				sleep 2
				downloadInstaller
			fi
		else
			downloadInstaller
		fi

		unsuccessfulDownload="TRUE"
		((loopCount++))
	done

	if [[ $unsuccessfulDownload == "TRUE" ]]; then
		message 0 "macOS Installer Downloaded 3 Times - Checksum is Not Valid"
		message 0 "Prompting user for error and exiting..."
		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$macOSicon" -heading "Error Downloading $macOSname" -description "We were unable to prepare your computer for $macOSname. Please contact the myTECH Helpdesk to report this error.  E-mail: helpdesk@tntech.edu. Phone: 931-372-3975." -iconSize 100 -button1 "OK" -defaultButton 1
		message 200 "Could not complete macOS Installer download."
	fi

	createFirstBootScript
	createLaunchDaemonPlist
	createFileVaultLaunchAgentRebootPlist

	# Begin install.
	# Check power one more time.
	pwrAdapter="$(/usr/bin/pmset -g ps)"
	if [[ ${pwrAdapter} == *"AC Power"* ]]; then
		pwrStatus="OK"
		message 0 "Power Check: OK - AC Power Detected"		
	else
		pwrStatus="ERROR"
		message 0 "Power Check: ERROR - No AC Power Detected"
	fi

	if [[ ${pwrStatus} == "OK" ]] && [[ ${spaceStatus} == "OK" ]] && [[ ${ramStatus} == "OK" ]]; then
		# Launch jamfHelper
		if (( userDialog == 0 )); then
			message 0 "Launching jamfHelper as FullScreen..."
			/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "" -icon "$macOSicon" -heading "$heading" -description "$description" &
			jamfHelperPID=$!
			message 0 "JamfHelper PID is $jamfHelperPID"
		fi

		if (( userDialog == 1 )); then
			message 0 "Launching jamfHelper as Utility Window..."
			/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$macOSicon" -heading "$heading" -description "$description" -iconSize 100 &
			jamfHelperPID=$!
			message 0 "JamfHelper PID is $jamfHelperPID"
		fi

		# Load LaunchAgent
		if [[ ${fvStatus} == "FileVault is On." ]] && [[ ${currentUser} != "root" ]]; then
			userID="$(id -u "${currentUser}")"
			launchctl bootstrap gui/"${userID}" /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
		fi

		# Begin Upgrade
		message 0 "Launching startosinstall..."
		# Check if eraseInstall is Enabled
		if (( eraseInstall == 1 )) && (( osMajor == 13 || osMajor == 14)); then
			message 0 "Script is configured for Erase and Install of macOS.  This will result in a \"factory default\" state after completion."
			# If convertToAPFS is explicitly set to NO, then we pass that on to the
			# installer.
			if (( osMajor == 13 )) && [[ $convertToAPFS == "NO" ]]; then
				[[ $debug == TRUE ]] && message 0 "Command is: \"$OSInstaller\"/Contents/Resources/startosinstall --agreetolicense --applicationpath \"$OSInstaller\" --converttoapfs \"$convertToAPFS\" --eraseinstall --nointeraction --pidtosignal \"$jamfHelperPID\" &"
				"$OSInstaller"/Contents/Resources/startosinstall --agreetolicense --applicationpath "$OSInstaller" --converttoapfs "$convertToAPFS" --eraseinstall --nointeraction --pidtosignal "$jamfHelperPID" &
			else
				[[ $debug == TRUE ]] && message 0 "Command is: \"$OSInstaller\"/Contents/Resources/startosinstall --agreetolicense --applicationpath \"$OSInstaller\" --eraseinstall --nointeraction --pidtosignal \"$jamfHelperPID\" &"
				"$OSInstaller"/Contents/Resources/startosinstall --agreetolicense --applicationpath "$OSInstaller" --eraseinstall --nointeraction --pidtosignal "$jamfHelperPID" &
			fi
		elif (( eraseInstall == 1 )) && ((osMajor < 13 )); then
			message 0 "Launching jamfHelper Dialog (Erase Requirements Not Met)..."
			/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "Invalid Install Options" -icon "$macOSicon" -heading "Invalid Erase and Install Options" -description "We were unable to Erase and Install $macOSname due to current macOS version < 10.13. Please contact the myTECH Helpdesk to report this error.  E-mail: helpdesk@tntech.edu. Phone: 931-372-3975." -iconSize 100 -button1 "OK" -defaultButton 1
			message 300 "Script is configured for Erase and Install of macOS.  Client version, however, is earlier than macOS 10.13 High Sierra and does not support this command.  Continuing with normal install."
		else
			if ((osMajor == 13 )) && [[ $convertToAPFS == "NO" ]]; then
				[[ $debug == TRUE ]] && message 0 "Command is: \"$OSInstaller\"/Contents/Resources/startosinstall --agreetolicense --applicationpath \"$OSInstaller\" --converttoapfs \"$convertToAPFS\" --nointeraction --pidtosignal \"$jamfHelperPID\" &"
				"$OSInstaller"/Contents/Resources/startosinstall --agreetolicense --applicationpath "$OSInstaller" --converttoapfs "$convertToAPFS" --nointeraction --pidtosignal "$jamfHelperPID" &
			else
				[[ $debug == TRUE ]] && message 0 "Command is: \"$OSInstaller\"/Contents/Resources/startosinstall --agreetolicense --applicationpath \"$OSInstaller\" --nointeraction --pidtosignal \"$jamfHelperPID\" &"
				"$OSInstaller"/Contents/Resources/startosinstall --agreetolicense --applicationpath "$OSInstaller" --nointeraction --pidtosignal "$jamfHelperPID" &
			fi
		fi
		/bin/sleep 3
	else
		# Remove Script
		/bin/rm -f "/Library/Scripts/tntech/finishOSInstall/finishOSInstall.sh"
		/bin/rm -f "/Library/LaunchDaemons/edu.tntech.cleanupOSInstall.plist"
		/bin/rm -f "/Library/LaunchAgents/com.apple.install.osinstallersetupd.plist"

		message 0 "Launching jamfHelper Dialog (Requirements Not Met)..."
		if ((osMajor == 13 )); then
			/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$macOSicon" -heading "Requirements Not Met" -description "We were unable to prepare your computer for $macOSname. Please ensure you are connected to power and that you have at least ${requiredMinimumSpace1013}GB of Free Space.  If you continue to experience this issue, please contact the myTECH Helpdesk. E-mail: helpdesk@tntech.edu. Phone: 931-372-3975." -iconSize 100 -button1 "OK" -defaultButton 1
		elif ((osMajor == 14 )); then
			/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$macOSicon" -heading "Requirements Not Met" -description "We were unable to prepare your computer for $macOSname. Please ensure you are connected to power and that you have at least ${requiredMinimumSpace1014}GB of Free Space.  If you continue to experience this issue, please contact the myTECH Helpdesk. E-mail: helpdesk@tntech.edu. Phone: 931-372-3975." -iconSize 100 -button1 "OK" -defaultButton 1
		else
			/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$macOSicon" -heading "Requirements Not Met" -description "We were unable to prepare your computer for $macOSname. Please ensure you are connected to power and that you have at least the minimum required free space for your selected operating system.  If you continue to experience this issue, please contact the myTECH Helpdesk. E-mail: helpdesk@tntech.edu. Phone: 931-372-3975." -iconSize 100 -button1 "OK" -defaultButton 1
		fi
	fi
}

[[ ! -d "${logDir}" ]] && mkdir -p "${logDir}"
[[ $debug == TRUE ]] && message 0 "Mode: debug"
message 0 "BEGIN: ${log} ${date}"
main "$@"
finish