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
#	Version is: 2018/10/09 @ 4:30pm
#
#	- 2018/10/09 @ 4:30pm by Jeff Rippy | Tennessee Tech University
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
#appDir="/Applications"
#app="${appDir}/app.app"
#appVersionFile="${app}/Contents/Info.plist"
caffeinatePID=""
debug="TRUE"
logDir="/tmp/${scriptName}"
log="${logDir}/${scriptName}.log"
mountPoint=""
computerName=""
loggedInUsername=""

# Script specific variables
# Transform GB into Bytes
gigabytes=$((1024 * 1024 * 1024))
macOSname=""

# OS Major and Minor version numbers for current OS install.
osVersion="$(/usr/bin/sw_vers -productVersion)"
osVersionMajor="$(echo "$osVersion" | awk -F. '{print $2}')"
osVersionMinor="$(echo "$osVersion" | awk -F. '{print $3}')"

# My minimum requirements for install
requiredMinimumRAM1013=4
requiredMinimumRAM1014=4
requiredMinimumSpace1013=15
requiredMinimumSpace1014=20

# Calculated requirements for install
minimumRAM1013=$((requiredMinimumRAM1013 * gigabytes))
minimumRAM1014=$((requiredMinimumRAM1014 * gigabytes))
minimumSpace1013=$((requiredMinimumSpace1013 * gigabytes))
minimumSpace1014=$((requiredMinimumSpace1014 * gigabytes))

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
		kill "${caffeinatePID}"
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
	local myCount=0
	local myDownloadTrigger="$4"
	local myInstallerPath="$1"
	local myInstallerVersion="$2"
	local myInstallESDChecksum="$3"
	local myInstallerVersionCheck=""
	local myJamfHelperPID=""

	local unsuccessfulDownload=""
	local validChecksum=""

	# Check for existing OS installer
	unsuccessfulDownload="TRUE"
	validChecksum="FALSE"
	myCount=0
	while ((myCount < 3 )); do
		if [[ -e "$myInstallerPath" ]]; then
			message 0 "$myInstallerPath found, checking version."
			myInstallerVersionCheck="$(/usr/libexec/PlistBuddy -c 'Print :"System Image Info":version' "$myInstallerPath/Contents/SharedSupport/InstallInfo.plist")"
			[[ $debug == TRUE ]] && message 0 "Installer Version from InstallInfo.plist is $myInstallerVersionCheck"
			if [[ $myInstallerVersionCheck == "$myInstallerVersion" ]]; then
				message 0 "Installer found, version matches. Verifying checksum..."
				verifyChecksum "$myInstallerPath" "$myInstallESDChecksum" validChecksum
				if [[ $validChecksum == "TRUE" ]]; then
					message 0 "$(date "+%Y%m%d.%H%M.%S") Download successfully verified."
					unsuccessfulDownload="FALSE"
					break
				else
					message 0 "Unable to verify checksum.  Removing installer download."
					/bin/rm -rf "$myInstallerPath"
				fi
			else
				message 0 "Installer found, but not the specified version. Deleting and downloading a new copy..."
				/bin/rm -rf "$myInstallerPath"
				/bin/sleep 2

				# Inform the user about the download.
				message 0 "Downloading $macOSname Installer..."
				/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType "hud" -windowPosition "ur" -title "$macOSname Upgrade" -alignHeading "center" -alignDescription "left" -description	"The installer resources for $macOSname need to download to your computer before the upgrade process can begin.  Please allow this process approximately 30 minutes to complete.  Your download speeds may vary." -lockHUD -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarDownloadsFolder.icns" -iconSize 100 &
				myJamfHelperPID=$!
				message 0 "JamfHelper PID is $myJamfHelperPID"

				# Run policy to cache installer
				[[ $debug == TRUE ]] && message 0 "Running policy \"jamf policy -event \"$myDownloadTrigger\"\"."
				/usr/local/bin/jamf policy -event "$myDownloadTrigger"

				# Kill jamfHelper HUD post download
				kill "$myJamfHelperPID"
			fi
		else
			# Inform the user about the download.
			message 0 "Downloading $macOSname Installer..."
			/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType "hud" -windowPosition "ur" -title "$macOSname Upgrade" -alignHeading "center" -alignDescription "left" -description	"The installer resources for $macOSname need to download to your computer before the upgrade process can begin.  Please allow this process approximately 30 minutes to complete.  Your download speeds may vary." -lockHUD -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarDownloadsFolder.icns" -iconSize 100
			myJamfHelperPID=$!
			message 0 "JamfHelper PID is $myJamfHelperPID"

			# Run policy to cache installer
			/usr/local/bin/jamf policy -event "$myDownloadTrigger"

			# Kill jamfHelper HUD post download
			kill "$myJamfHelperPID"
		fi

		unsuccessfulDownload="TRUE"
		((myCount++))
	done

	if [[ $unsuccessfulDownload == "TRUE" ]]; then
		message 0 "macOS Installer Downloaded 3 Times - Checksum is Not Valid"
		message 0 "Prompting user for error and exiting..."
		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType "utility" -title "$macOSname Upgrade" -icon "$myInstallerPath/Contents/Resources/InstallAssistant.icns" -heading "Error Downloading $macOSname" -description "We were unable to prepare your computer for $macOSname. Please contact the myTECH Helpdesk to report this error.
E-mail: helpdesk@tntech.edu.
Phone: 931-372-3975." -iconSize 100 -button1 "OK" -defaultButton 1 &
		message 1002 "Could not complete macOS Installer download."
	fi

	return
}

function verifyChecksum()
{
	local myInstallerPath="$1"
	local myInstallESDChecksum="$2"
	local myInstallerChecksum=""
	local myValidChecksum=""

	myValidChecksum="FALSE"
	if [[ -n "$myInstallESDChecksum" ]]; then
		myInstallerChecksum="$(/sbin/md5 -q "$myInstallerPath/Contents/SharedSupport/InstallESD.dmg")"
		if [[ "$myInstallerChecksum" == "$myInstallESDChecksum" ]]; then
			myValidChecksum="TRUE"
			message 0 "Valid Checksum: $myValidChecksum"
		else
			myValidChecksum="FALSE"
			message 0 "Valid Checksum: $myValidChecksum"
		fi
	else
		myValidChecksum="TRUE"
	fi

	eval "$3=\$myValidChecksum"
	return
}

function createFirstBootScript()
{
	local myInstallerPath="$1"

	# This creates the First Boot Script to complete the install.
	/bin/mkdir -p /Library/Scripts/tntech/finishOSInstall
	cat << EOF > "/Library/Scripts/tntech/finishOSInstall/finishOSInstall.sh"
#!/bin/bash
# First Run Script to remove the installer.
# Clean up files
/bin/rm -fdr \"$myInstallerPath\"
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
	local myInstallerPath="$1"
	local myProgArgument="osinstallersetupd"

	# If the drive is encrypted, create this LaunchAgent for authenticated reboots.
	# The progArgument is different depending on the currently installed operating system.
	if (( osVersionMajor == 10 )); then
		myProgArgument="osinstallersetupplaind"
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
			<string>$myInstallerPath/Contents/Frameworks/OSInstallerSetup.framework/Resources/$myProgArgument</string>
	</array>
</dict>
</plist>
EOF

	/usr/sbin/chown root:wheel /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
	/bin/chmod 644 /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
}

function checkFreeSpace()
{
	local myFreeSpace=""
	local myMinimumSpace="$1"
	local mySpaceStatus=""

	# Get current free space available.
	myFreeSpace=$(diskutil info / | awk -F'[()]' '/Free Space|Available Space/ {print $2}' | sed -e 's/\ Bytes//')
	if (( myFreeSpace < myMinimumSpace )); then
		mySpaceStatus="ERROR"
		message 0 "Disk Check: $mySpaceStatus - $myFreeSpace Free Space Detected.  This is below threshold of $myMinimumSpace required."
	else
		mySpaceStatus="OK"
		message 0 "Disk Check: $mySpaceStatus - $myFreeSpace Free Space Detected."
	fi

	eval "$2=\$mySpaceStatus"
	return
}

function checkRAM()
{
	local myInstalledRAM=""
	local myMinimumRAM="$1"
	local myRAMStatus=""

	# Check amount of RAM installed
	myInstalledRAM="$(/usr/sbin/sysctl -n hw.memsize)"
	if (( myInstalledRAM < myMinimumRAM )); then
		myRAMStatus="ERROR"
		message 0 "RAM Check: $myRAMStatus - $myInstalledRAM RAM Detected.  This is below threshold of $myMinimumRAM required."
	else
		myRAMStatus="OK"
		message 0 "RAM Check: $myRAMStatus - $myInstalledRAM RAM Detected."
	fi

	eval "$2=\$myRAMStatus"
	return
}

function checkPower()
{
	local myCount=0
	local myPowerAdapter=""
	local myPowerStatus=""

	while ((myCount < 3)); do
		myPowerAdapter="$(/usr/bin/pmset -g ps)"
		if [[ $myPowerAdapter == *"AC Power"* ]]; then
			myPowerStatus="OK"
			message 0 "Power Check: $myPowerStatus - AC Power Detected"
			break
		else
			message 0 "Launching jamfHelper Dialog (Power Requirements Not Met)..."
			/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType "utility" -title "Power Status Error" -heading "AC Adapter Not Plugged In." -description "AC adapter not connected.  Please connect to power source before proceeding." -button1 "OK" -defaultButton 1 -timeout 120 -countdown
			myPowerStatus="ERROR"
			message 0 "Power Check: $myPowerStatus - No AC Power Detected"
		fi
		((myCount++))
	done

	eval "$1=\$myPowerStatus"
	return
}

function checkFileVault()
{
	# Check if FileVault Enabled
	local myFvStatus=""
	local myUserID=""

##	# Get Current User
##	currentUser="$(stat -f %Su /dev/console)"

##	if [[ ${fvStatus} == "FileVault is On." ]] && [[ ${currentUser} != "root" ]]; then
##		userID="$(id -u "${currentUser}")"
##		launchctl bootstrap gui/"${userID}" /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
	myFvStatus="$(/usr/bin/fdesetup status | head -1)"
	if [[ $myFvStatus == "FileVault is On." ]] && [[ $loggedInUsername != "root" ]]; then
		myUserID="$(id -u "$loggedInUsername")"
		launchctl bootstrap gui/"$myUserID" /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
	fi
}

function main()
{
	# For jss scripts, the following is true:
	# Variable $1 is defined as mount point
	# Variable $2 is defined as computer name
	# Variable $3 is defined as username (That is the currently logged in user or root if at the loginwindow.

	# Caffeinate - keeps the computer awake even if the screen is closed.
	/usr/bin/caffeinate -dis &
	caffeinatePID=$!
	[[ $debug == TRUE ]] && message 0 "Disabling sleep during script.  Caffeinate PID is $caffeinatePID."

	local convertToAPFS=""
	local downloadTrigger=""
	local eraseInstall=""
	local installerPath=""
	local installerVersion=""
	local installerVersionMajor=""
	local installerVersionMinor=""
	local installESDChecksum=""
	local jamfHelperPID=""
	local minimumRAM=""
	local minimumSpace=""
	local powerStatus=""
	local ramStatus=""
	local requiredMinimumSpace=""
	local spaceStatus=""
	local validChecksum=""

	if (( osVersionMajor == 10 && osVersionMinor < 5)) || (( osVersionMajor < 10)); then
		message 0 "Launching jamfHelper Dialog (Requirements Not Met)..."
		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "Mac OS X Version Not Supported" -heading "Requirements Not Met" -alignHeading="center" -description "This upgrade method is only supported on computers running Mac OS X 10.10.5 or newer.  Please contact the myTECH Helpdesk for assistance.
email: helpdesk@tntech.edu.
Phone: 931-372-3975." -alignDescription "left" -button1 "OK" -defaultButton 1 -timeout "600"
		message 1000 "This upgrade method is only supported on Mac OS X machines running 10.10.5 and newer.  Please contact the myTECH Helpdesk for assistance."		
	fi

	# Perform a jamf recon first so that an updated restricted software list is downloaded
	# such that this machine will be able to run the installer.
	/usr/local/bin/jamf recon

	# Get the variables passed in and clean up if necessary.
	mountPoint="$1"
	[[ $debug == TRUE ]] && message 0 "Mount Point BEFORE stripping a trailing slash (/) is $mountPoint."
	mountPoint="${mountPoint%/}"	# This removes a trailing '/' if present.
	[[ $debug == TRUE ]] && message 0 "Mount Point AFTER stripping a trailing slash (/) is $mountPoint."

	computerName="$2"
	[[ $debug == TRUE ]] && message 0 "Computer name is $computerName."

	loggedInUsername="$3"
	if [[ -z $loggedInUsername ]]; then
		message 10 "No user currently logged in.  For a macOS install from Self Service, a user MUST be logged in."
	else
		loggedInUsername="$(echo "$loggedInUsername" | tr '[:upper:] [:lower:]')"
		[[ $debug == TRUE ]] && message 0 "Logged in Username is $loggedInUsername."
	fi

	# Specify full path to installer. Use Parameter 4 in the JSS or specify here.
	# Example 1: installerPath="/Applications/Install macOS High Sierra.app"
	# Example 2: installerPath="/Applications/Install macOS Mojave.app"
	installerPath="$4"
	if [[ -z $installerPath ]]; then
		message 20 "No path to macOS Installer specified.  Acceptable value is \"/Applications/Install macOS <Version Name>.app\""
	else
		[[ $debug == TRUE ]] && message 0 "macOS installer path is now \"$installerPath\"."
	fi
	# Get title of the OS, i.e. macOS High Sierra
	# Use these values for the user dialog box
	macOSname="$(echo "$installerPath" | sed 's/^\/Applications\/Install \(.*\)\.app$/\1/')"

	# Version of installer. Use Parameter 5 in the JSS or specify here.
	# Command to find version: $(/usr/libexec/PlistBuddy -c 'Print :"System Image Info":version' "/Applications/Install macOS High Sierra.app/Contents/SharedSupport/InstallInfo.plist")
	# Example: 10.13.6
	installerVersion="$5"
	if [[ -n $installerVersion ]]; then
		[[ $debug == TRUE ]] && message 0 "macOS installer version specified as \"$installerVersion\"."
	else
		message 30 "No macOS installer version specified. Please input the version of the installer that is being used."
	fi

	installerVersionMajor="$(/bin/echo "$installerVersion" | /usr/bin/awk -F. '{print $2}')"
	installerVersionMinor="$(/bin/echo "$installerVersion" | /usr/bin/awk -F. '{print $3}')"

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
		[[ $debug == TRUE ]] && message 0 "Specified download trigger is \"$downloadTrigger\"."
	else
		message 40 "No download trigger specified."
	fi

	# MD5 checksum of InstallESD.dmg
	# Optional variable used to compare the downloaded installer and verify as good.
	# This can be blank if you do not want to use this functionality.
	# Example Command: /sbin/md5 "/Applications/Install macOS High Sierra.app/Contents/SharedSupport/InstallESD.dmg"
	# Example: b15b9db3a90f9ae8a9df0f81741efa2b
	installESDChecksum="$7"
	if [[ -n  $installESDChecksum ]]; then
		[[ $debug == TRUE ]] && message 0 "InstallESD checksum specified as \"$installESDChecksum\"."
	else
		message 0 "No InstallESD checksum specified.  It is optional."
		validChecksum=1
	fi

	# eraseInstall is ONLY VALID if the macOS client is 10.13+ and the Installer
	# is 10.13.4+
	eraseInstall="$8"
	if [[ -z $eraseInstall ]]; then
		eraseInstall=0
	fi

	if (( installerVersionMajor < 13 )) || (( installerVersionMajor == 13 && installerVersionMinor < 4 )); then
		message 0 "macOS installer version does not qualify for erase and install.  Version is macOS 10.$installerVersionMajor.$installerVersionMinor.  Full version is macOS $installerVersion."
		eraseInstall=0
	fi

	if (( eraseInstall == 0 )); then
		message 0 "Erase Install option not specified or 0.  Assuming default of upgrade only.  The erase function will not happen."
	elif (( eraseInstall == 1 )); then
		message 0 "Erase Install has been specified.  This will reset the computer to a \"factory default\" state.  This is only valid for macOS installer versions 10.13.4+"
	else
		message 50 "Unknown option passed to eraseInstall variable: $eraseInstall.  Exiting."
	fi

	# convertToAPFS is ONLY VALID for macOS 10.13 High Sierra installs.
	# APFS was introduced in macOS 10.13 and is optional during the transition.
	# It is required for macOS 10.14 Mojave.
	convertToAPFS="$9"
	if [[ -z $convertToAPFS ]]; then
		convertToAPFS=1
	fi

	if (( convertToAPFS == 1)); then
		[[ $debug == TRUE ]] && message 0 "Default action to convert to APFS has been selected."
	elif (( convertToAPFS == 0 )); then
		message 0 "Convert to APFS has been specified as No.  Action is to NOT convert filesystem to APFS.  This is only applicable to macOS 10.13.  macOS 10.14 will not honor this setting."
	else
		message 60 "Unknown option passed to convertToAPFS variable: $convertToAPFS.  Exiting."
	fi

	case "$installerVersionMajor" in
		13)
			minimumRAM="$minimumRAM1013"
			minimumSpace="$minimumSpace1013"
			requiredMinimumSpace="$requiredMinimumSpace1013"
			;;
		14)
			minimumRAM="$minimumRAM1014"
			minimumSpace="$minimumSpace1014"
			requiredMinimumSpace="$requiredMinimumSpace1014"
			;;
		*)
			message 1001 "Unknown Operating System."
			;;
	esac

	checkFreeSpace "$minimumSpace" spaceStatus
	checkRAM "$minimumRAM" ramStatus
	checkPower powerStatus
	downloadInstaller "$installerPath" "$installerVersion" "$installESDChecksum" "$downloadTrigger"
	createFirstBootScript "$installerPath"
	createLaunchDaemonPlist
	createFileVaultLaunchAgentRebootPlist "$installerPath"

	# Begin install.
	checkPower powerStatus

	if [[ $powerStatus == "OK" ]] && [[ $spaceStatus == "OK" ]] && [[ $ramStatus == "OK" ]]; then
		# Launch jamfHelper
		message 0 "Launching jamfHelper as FullScreen..."
		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType "fs" -icon "$installerPath/Contents/Resources/InstallAssistant.icns" -heading "Please wait as your computer is prepared for $macOSname..." -description "This process will take approximately 5-10 minutes. Once completed, your computer will reboot and begin the upgrade process." &
		jamfHelperPID=$!
		message 0 "JamfHelper PID is $jamfHelperPID"

		# Load LaunchAgent
		checkFileVault

		# Begin Upgrade
		message 0 "Launching startosinstall..."
		case "$installerVersionMajor" in
			14)
				# 10.14 does not honor --converttoapfs or --applicationpath.
				# They are deprecated.
				# Erase install specified as NO
				if ((eraseInstall == 0)); then
					[[ $debug == TRUE ]] && message 0 "Command is: \"$installerPath\"/Contents/Resources/startosinstall --agreetolicense --nointeraction --eraseInstall --pidtosignal \"$jamfHelperPID\" &"
					/bin/sleep 10
					"$installerPath"/Contents/Resources/startosinstall --agreetolicense --nointeraction --eraseInstall --pidtosignal "$jamfHelperPID" &
					/bin/sleep 5
				# Erase install specified as YES
				elif ((eraseInstall == 1)); then
					[[ $debug == TRUE ]] && message 0 "Command is: \"$installerPath\"/Contents/Resources/startosinstall --agreetolicense --nointeraction --pidtosignal \"$jamfHelperPID\" &"
					/bin/sleep 10
					"$installerPath"/Contents/Resources/startosinstall --agreetolicense --nointeraction --pidtosignal "$jamfHelperPID" &
					/bin/sleep 5
				fi
				;;
			13)
				# Convert to APFS specified as NO, erase install specified as NO
				if ((convertToAPFS == 0 && eraseInstall == 0)); then
					[[ $debug == TRUE ]] && message 0 "Command is: \"$installerPath\"/Contents/Resources/startosinstall --agreetolicense --applicationpath \"$installerPath\" --nointeraction --converttoapfs \"NO\" --pidtosignal \"$jamfHelperPID\" &"
					/bin/sleep 10
					"$installerPath"/Contents/Resources/startosinstall --agreetolicense --applicationpath "$installerPath" --nointeraction --converttoapfs "NO" --pidtosignal "$jamfHelperPID" &
					/bin/sleep 5
				# Convert to APFS specified as NO, erase install specified as YES
				elif ((convertToAPFS == 0 && eraseInstall == 1)); then
					[[ $debug == TRUE ]] && message 0 "Command is: \"$installerPath\"/Contents/Resources/startosinstall --agreetolicense --applicationpath \"$installerPath\" --nointeraction --converttoapfs \"NO\" --eraseInstall --pidtosignal \"$jamfHelperPID\" &"
					/bin/sleep 10
					"$installerPath"/Contents/Resources/startosinstall --agreetolicense --applicationpath "$installerPath" --nointeraction --converttoapfs "NO" --eraseInstall --pidtosignal "$jamfHelperPID" &
					/bin/sleep 5
				# Convert to APFS default YES, erase install specified as NO
				elif ((convertToAPFS == 1 && eraseInstall == 0)); then
					[[ $debug == TRUE ]] && message 0 "Command is: \"$installerPath\"/Contents/Resources/startosinstall --agreetolicense --applicationpath \"$installerPath\" --nointeraction --pidtosignal \"$jamfHelperPID\" &"
					/bin/sleep 10
					"$installerPath"/Contents/Resources/startosinstall --agreetolicense --applicationpath "$installerPath" --nointeraction --pidtosignal "$jamfHelperPID" &
					/bin/sleep 5
				# Convert to APFS default YES, erase install specified as YES
				elif ((convertToAPFS == 1 && eraseInstall == 1)); then
					[[ $debug == TRUE ]] && message 0 "Command is: \"$installerPath\"/Contents/Resources/startosinstall --agreetolicense --applicationpath \"$installerPath\" --nointeraction --eraseInstall --pidtosignal \"$jamfHelperPID\" &"
					/bin/sleep 10
					"$installerPath"/Contents/Resources/startosinstall --agreetolicense --applicationpath "$installerPath" --nointeraction --eraseInstall --pidtosignal "$jamfHelperPID" &
					/bin/sleep 5
				fi
				;;
		esac
	else
		# Remove Script
		/bin/rm -f "/Library/Scripts/tntech/finishOSInstall/finishOSInstall.sh"
		/bin/rm -f "/Library/LaunchDaemons/edu.tntech.cleanupOSInstall.plist"
		/bin/rm -f "/Library/LaunchAgents/com.apple.install.osinstallersetupd.plist"

		message 0 "Launching jamfHelper Dialog (Requirements Not Met)..."
		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType "utility" -title "$macOSname Upgrade" -icon "$installerPath/Contents/Resources/InstallAssistant.icns" -heading "Requirements Not Met" -description "We were unable to prepare your computer for $macOSname. Please ensure you are connected to power and that you have at least ${requiredMinimumSpace}GB of Free Space.  If you continue to experience this issue, please contact the myTECH Helpdesk.
E-mail: helpdesk@tntech.edu.
Phone: 931-372-3975." -iconSize 100 -button1 "OK" -defaultButton 1
	fi
}

[[ ! -d "${logDir}" ]] && mkdir -p "${logDir}"
[[ $debug == TRUE ]] && message 0 "Mode: debug"
message 0 "BEGIN: ${log} ${date}"
main "$@"
finish