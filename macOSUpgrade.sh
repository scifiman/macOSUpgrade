#!/bin/bash
################################################################################
#
#	Copyright (c) 2018, Jamf.  All rights reserved.
#
#		Redistribution and use in source and binary forms, with or without
#		modification, are permitted provided that the following conditions
#		are met:
#		  * Redistribution of source code must retain the above copyright
#			notice, this list of conditions and the following disclaimer.
#		  * Redistributions in binary form must reproduce the above copyright
#			notice, this list of conditions and the following disclaimer in the
#			documentation and/or other materials provided with the distribution.
#		  * Neither the name of the Jamf nor the names of its contributors
#			may be used to endorse or promote products derived from this
#			software without specific prior written permission.
#
#		THIS SOFTWARE IS PROVIDED BY JAMF SOFTWARE, LLC "AS IS" AND ANY
#		EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#		IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
#		PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL JAMF SOFTWARE, LLC BE LIABLE
#		FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
#		CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
#		SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
#		INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#		CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
#		ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
#		THE POSSIBILITY OF SUCH DAMAGE.
#
#################################################################################
#	SUPPORT FOR THIS PROGRAM
#		No support is offered
#		The copyright notice is left in place as this was originally written
#			by Jamf.
#
#################################################################################
#	ABOUT THIS PROGRAM
#
#	NAME
#		macOSUpgrade.sh
#
#	SYNOPSIS
#		This script was designed to be used in a Self Service policy to ensure
#		specific requirements have been met before proceeding with an inplace
#		upgrade of the macOS, as well as to address changes Apple has made to
#		the ability to complete macOS upgrades silently.
#
################################################################################
#
#	REQUIREMENTS
#		- Jamf Pro
#		- macOS Clients running version 10.10.5 or later
#		- macOS Installer version 10.12.4 or later
#		- eraseInstall option is ONLY support with macOS Installer 10.13.4
#			or later and macOS Clients version 10.13 or later
#
################################################################################
#
#	HISTORY
#
#	Version is: YYYY/MM/DD @ HH:MMam/pm
#	Version is: 2018/10/19 @ 9:00am
#
#	- 2018/10/19 @ 9:00am by Jeff Rippy | Tennessee Tech University
#		- Updated to reflect some changes from Joshua's Master Branch.
#			v. 2.7.2.1
#	- 2018/09/28 by Joshua Roskos | Jamf
#		- Incorporated several commits on Github.
#		- Version incremented to 2.7.2.1
#	- 2018/09/18 @ 4:30pm by Jeff Rippy | Tennessee Tech University
#		- Forked from Joshua Roskos original project and modified for
#			Tennessee Tech
#		- Github source: https://github.com/scifiman/macOSUpgrade
#	- 2017/01/05 by Joshua Roskos | Jamf
#		- Initial Script
#		- Github source: https://github.com/kc9wwh/macOSUpgrade
# 
################################################################################
#
#	DEFINE VARIABLES & READ IN PARAMETERS
#
################################################################################

scriptName="macOSUpgrade"
date="$(date "+%Y%m%d.%H%M.%S")"
#appDir="/Applications"
#app="${appDir}/App"
#AppVersionFile="${app}/Contents/Info.plist"
debug="TRUE"
logDir="/tmp/${scriptName}"
log="${logDir}/${scriptName}.log"
logDate="${logDir}/${scriptName}.log.$date"
mountPoint=""
computerName=""
loggedInUsername=""
osVersion="$(/usr/bin/sw_vers -productVersion)"
osVersionMajor="$(/bin/echo "$osVersion" | /usr/bin/awk -F. '{print $2}')"
osVersionMinor="$(/bin/echo "$osVersion" | /usr/bin/awk -F. '{print $3}')"
caffeinatePID=""

gigabytes=$((1024 * 1024 * 1024))
macOSname=""

# Minimum requirements for install.  These are my required minimums for Tennessee Tech.
# Actual system requirements Mojave: https://support.apple.com/en-us/HT201475
requiredMinimumRAM1013=4
requiredMinimumRAM1014=4
requiredMinimumSpace1013=15
requiredMinimumSpace1014=20

# Don't change these values.
# Calculated requirements for install.
minimumRAM1013=$((requiredMinimumRAM1013 * gigabytes))
minimumRAM1014=$((requiredMinimumRAM1014 * gigabytes))
minimumSpace1013=$((requiredMinimumSpace1013 * gigabytes))
minimumSpace1014=$((requiredMinimumSpace1014 * gigabytes))

################################################################################
#
# SCRIPT CONTENTS - DO NOT MODIFY BELOW THIS LINE
#
################################################################################

function finish()
{
	local exitStatus=$1
	[[ $exitStatus ]] || exitStatus=0
	if [[ -n $caffeinatePID ]]; then
		[[ $debug == TRUE ]] && message 0 "Stopping caffeinate PID: $caffeinatePID."
		/bin/kill "$caffeinatePID"
	fi
	/bin/echo "FINISH: $log" | /usr/bin/tee -a "$log"
	/usr/bin/logger -f "$log"
	exit $exitStatus
}

function warningMessage()
{
	local thisCode=$1
	local thisMessage="$2"
	[[ $thisMessage ]] || thisMessage="Unknown Warning"
	/bin/echo "WARNING: ($thisCode) $thisMessage" | /usr/bin/tee -a "$log"
}

function normalMessage()
{
	local thisMessage="$1"
	[[ $thisMessage ]] || return
	/bin/echo "$thisMessage" | /usr/bin/tee -a "$log"
}

function errorMessage()
{
	local thisCode=$1
	local thisMessage="$2"
	/bin/echo "ERROR: ($thisCode) $thisMessage" | /usr/bin/tee -a "$log"
	finish "$thisCode"
}

function message()
{
	local thisCode=$1
	local thisMessage="$2"
	
	(( thisCode > 0 )) && errorMessage "$thisCode" "$thisMessage"
	(( thisCode < 0 )) && warningMessage "$thisCode" "$thisMessage"
	(( thisCode == 0 )) && normalMessage "$thisMessage"
}

function checkFreeSpace()
{
	local myFreeSpace=""
	local myFreeSpaceGB=""
	local myMinimumSpace="$1"
	local myMinimumSpaceGB=""
	local mySpaceStatus=""

	# Get the current amount of free space available.
	myFreeSpace="$(/usr/sbin/diskutil info / | /usr/bin/awk -F'[()]' '/Free Space|Available Space/ {print $2}' | /usr/bin/sed -e 's/\ Bytes//')"
	myFreeSpaceGB=$((myFreeSpace / gigabytes))
	myMinimumSpaceGB=$((myMinimumSpace / gigabytes))

	if ((myFreeSpace < myMinimumSpace)); then
		mySpaceStatus="ERROR"
		message 300 "Disk Check: $mySpaceStatus - $myFreeSpaceGB GB detected.  This is below the minimum threshold of $myMinimumSpaceGB GB required."
	else
		mySpaceStatus="OK"
		message 0 "Disk Check: $mySpaceStatus - $myFreeSpaceGB GB Free Space Detected."
	fi

	eval "$2=\$mySpaceStatus"
}

function checkRAM()
{
	local myInstalledRAM=""
	local myMinimumRAM="$1"
	local myRAMStatus=""
	local myInstalledRAMGB=""
	local myMinimumRAMGB=""

	# Get the current amount of installed RAM.
	myInstalledRAM="$(/usr/sbin/sysctl -n hw.memsize)"
	myInstalledRAMGB=$((myInstalledRAM / gigabytes))
	myMinimumRAMGB=$((myMinimumRAM / gigabytes))

	if ((myInstalledRAM < myMinimumRAM)); then
		myRAMStatus="ERROR"
		message 310 "RAM Check: $myRAMStatus - $myInstalledRAMGB GB detected.  This is below the threshold of $myMinimumRAMGB GB required."
	else
		myRAMStatus="OK"
		message 0 "RAM Check: $myRAMStatus - $myInstalledRAMGB GB Detected."
	fi

	eval "$2=\$myRAMStatus"
}

function checkPower()
{
	local myCount=0
	local myPowerAdapter=""
	local myPowerStatus=""
	local myWindowType="utility"
	local myWindowPosition="ur"
	local myTitle="Power Status Error"
	local myHeading="AC Adapter Not Connected"
	local myDescription="Please connect to a power outlet before proceeding with this install."
	local myAlignDescription="left"
	local myAlignHeading="justified"
	local myAlignCountdown="right"
	local myButton1Label="OK"
	local myIcon="/System/Library/PreferencePanes/EnergySaver.prefPane/Contents/Resources/EnergySaver.icns"
	local myIconSize=100
	local myTimeout=120

	while ((myCount < 3)); do
		myPowerAdapter="$(/usr/bin/pmset -g ps)"
		if [[ $myPowerAdapter == *"AC Power"* ]]; then
			myPowerStatus="OK"
			message 0 "Power Check: $myPowerStatus - AC power detected."
			break
		else
			myPowerStatus="ERROR"
			message 0 "Power Check: $myPowerStatus - No AC power detected."
			message 0 "Launching jamfHelper Dialog (Power Requirements Not Met)..."
			/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType "$myWindowType" -windowPosition "$myWindowPosition" -title "$myTitle" -heading "$myHeading" -alignHeading "$myAlignHeading" -description "$myDescription" -alignDescription "$myAlignDescription" -icon "$myIcon" -iconSize "$myIconSize" -button1 "$myButton1Label" -defaultButton 1 -timeout "$myTimeout" -countdown -alignCountdown "$myAlignCountdown"
		fi
		((myCount++))
	done

	eval "$1=\$myPowerStatus"
}

function getFileVaultStatus()
{
	local myFvStatus=""

	myFvStatus="$(/usr/bin/fdesetup status | head -1)"
	message 0 "FileVault Check: $myFvStatus"

	eval "$1=\myFvStatus"
}

function downloadInstaller()
{
	local myDownloadTrigger="$1"
	local myWindowType="hud"
	local myWindowPosition="ur"
	local myTitle="Downloading $macOSname Installer"
	local myDescription="Downloading macOS installer.  This may take up to 30 minutes, but usually takes much less time.  Please do not restart or power off your computer during this time."
	local myAlignDescription="left"
	local myIcon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/sidebarDownloadsFolder.icns"
	local myIconSize=100
	local myJamfHelperPID=""

	[[ $debug == TRUE ]] && message 0 "Downloading macOS Installer."
	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType "$myWindowType" -windowPosition "$myWindowPosition" -title "$myTitle" -description "$myDescription" -alignDescription "$myAlignDescription" -icon "$myIcon" -iconSize "$myIconSize" -lockHUD &
	myJamfHelperPID=$!

	/usr/local/bin/jamf policy -event "$myDownloadTrigger"
	/bin/kill "$myJamfHelperPID"
}

function verifyChecksum()
{
	local myInstallerPath="$1"
	local myInstallESDChecksum="$2"
	local myChecksum=""
	local myValidChecksum=0

	if [[ -n $myInstallESDChecksum ]]; then
		myChecksum="$(/sbin/md5 -q "$myInstallerPath/Contents/SharedSupport/InstallESD.dmg")"
		if [[ $myChecksum == "$myInstallESDChecksum" ]]; then
			myValidChecksum=1
			message 0 "The macOS installer checksum is valid ($myValidChecksum)."
			eval "$3=\$myValidChecksum"
			return
		else
			message 0 "The macOS installer checksum is invalid ($myValidChecksum)."
			message 0 "Retrying download."
			/bin/rm -rf "$myInstallerPath"
			/bin/sleep 2
			downladInstaller
		fi
	else
		# Checksum null, assumed valid
		myValidChecksum=1
		message 0 "Checksum was null and therefore assume valid ($myValidChecksum)."
		eval "$3=\$myValidChecksum"
		return
	fi
}

function createFirstBootScript()
{
	local myInstallerPath="$1"

	/bin/mkdir -p /usr/local/tntech/finishOSInstall
	/bin/cat << EOF > "/usr/local/tntech/finishOSInstall/finishOSInstall.sh"
#!/bin/bash
# First run script to remove the installer and associated files.
/bin/rm -fr "$myInstallerPath"
/bin/sleep 2
# Update inventory
/usr/local/bin/jamf recon
# Remove LaunchDaemon
/bin/rm -f /Library/LaunchDaemons/edu.tntech.cleanupOSInstall.plist
# Remove this script
/bin/rm -fr /usr/local/tntech/finishOSInstall
EOF

	/usr/sbin/chown -R root:admin /usr/local/tntech/finishOSInstall
	/bin/chmod -R 755 /usr/local/tntech/finishOSInstall
	message 0 "First Boot Script successfully created."
}

function createLaunchDaemonPlist()
{
	/bin/cat << EOF > "/Library/LaunchDaemons/edu.tntech.cleanupOSInstall.plist"
<?xml version="1.0" encoding="UTF-8" ?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>edu.tntech.cleanupOSInstall.plist</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>-c</string>
		<string>/usr/local/tntech/finishOSInstall/finishOSInstall.sh</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF

	/usr/sbin/chown root:wheel /Library/LaunchDaemons/edu.tntech.cleanupOSInstall.plist
	/bin/chmod 644 /Library/LaunchDaemons/edu.tntech.cleanupOSInstall.plist

	message 0 "LaunchDaemon successfully created."
}

function createLaunchAgentFileVaultRebootPlist()
{
	local myInstallerPath="$1"
	local myProgramArgument="osinstallersetupd"

	if ((osVersionMajor == 10)); then
		myProgramArgument="osinstallersetupplaind"
	fi

# Program Argument string may need extra quotes if this doesn't work.
	/bin/cat << EOF > "/Library/LaunchAgents/com.apple.install.osinstallersetupd.plist"
<?xml version="1.0" encoding="UTF-8" ?>
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
		<string>$myInstallerPath/Contents/Frameworks/OSInstallerSetup.framework/Resources/$myProgramArgument</string>
	</array>
</dict>
</plist>
EOF

	/usr/sbin/chown root:wheel /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
	/bin/chmod 644 /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist

	message 0 "LaunchAgent for FileVault Reboot successfully created."
}

function main()
{
	# For jss scripts, the following is true:
	# Variable $1 is defined as mount point
	# Variable $2 is defined as computer name
	# Variable $3 is defined as username (That is the currently logged in user or root if at the loginwindow.

	local mountPoint=""
	local computerName=""
	local loggedInUsername=""
	local installerPath=""
	local installerVersion=""
	local installerVersionMajor=""
	local installerVersionMinor=""
	local downloadTrigger=""
	local installESDChecksum=""
	local validChecksum=0
	local eraseInstall=""
	local minimumSpace=""
	local minimumRAM=""
	local spaceStatus=""
	local ramStatus=""
	local powerStatus=""
	local fvStatus=""
	local windowType=""
	local windowPosition=""
	local title=""
	local heading=""
	local description=""
	local alignDescription=""
	local alignHeading=""
	local alignCountdown=""
	local button1Label=""
	local icon=""
	local iconSize=""
	local timeout=""
	local count=""
	local successfulDownload=""
	local downloadVersion=""
	local jamfHelperPID=""

	# Caffeinate
	/usr/bin/caffeinate -dis &
	caffeinatePID=$!
	[[ $debug == TRUE ]] && message 0 "Disabling sleep during script.  Caffeinate PID is $caffeinatePID."

	if ((osVersionMajor == 10 && osVersionMinor < 5)) || ((osVersionMajor < 10)); then
		windowType="utility"
		windowPosition="center"
		title="Currently Installed Mac OS X (macOS) Version Not Supported"
		heading="Operating System Requirements Not Met"
		description="This upgrade method is only supported on machines running Mac OS X 10.10.5 and newer.
Please contact the myTECH Helpdesk for assistance.
email: helpdesk@tntech.edu, phone: (931) 372-3975"
		alignDescription="left"
		alignHeading="center"
		alignCountdown="right"
		button1Label="OK"
		timeout=120

		message 0 "Launching jamfHelper Dialog (OS Requirements Not Met)..."
		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType "$windowType" -windowPosition "$windowPosition" -title "$title" -heading "$heading" -alignHeading "$alignHeading" -description "$description" -alignDescription "$alignDescription" -button1 "$button1Label" -defaultButton 1 -timeout "$timeout" -countdown -alignCountdown "$alignCountdown"
		message 500 "This upgrade method is only supported on machines running Mac OS X 10.10.5 and later. Please contact the myTECH Helpdesk for assistance.  email: helpdesk@tntech.edu, phone: (931) 372-3975"
	fi

	# Verify arguments are passed in.  Otherwise exit.
	if [[ "$#" -eq 0 ]]; then
		message 99 "No parameters passed to script."	# We should never see this.
	fi

	# Get the variables passed in and clean up if necessary.
	mountPoint="$1"
	[[ $debug == TRUE ]] && message 0 "Mount Point BEFORE stripping a trailing slash (/) is $mountPoint."
	mountPoint="${mountPoint%/}"	# This removes a trailing '/' if present.
	[[ $debug == TRUE ]] && message 0 "Mount Point AFTER stripping a trailing slash (/) is $mountPoint."

	computerName="$2"
	[[ $debug == TRUE ]] && message 0 "Computer name has been set to \"$computerName\"."

	loggedInUsername="$3"
	if [[ -z $loggedInUsername ]]; then
		message 10 "No user currently logged in."
	else
		loggedInUsername="$(echo "$loggedInUsername" | tr "[:upper:]" "[:lower:]")"
		[[ $debug == TRUE ]] && message 0 "Logged in Username has been set to \"$loggedInUsername\"."
	fi

	# Specify full path to installer.  Use parameter 4 in the Jamf Pro Server
	# Ex: "/Applications/Install macOS High Sierra.app"
	# Ex: "/Applications/Install macOS Mojave.app"
	installerPath="$4"
	if [[ -z $installerPath ]]; then
		message 20 "The macOS installer path was not specified.  Example: \"/Applications/Install macOS High Sierra.app\""
	fi
	[[ $debug == TRUE ]] && message 0 "The macOS installer path has been set to \"$installerPath\"."

	# Go ahead and get the macOS name from the installer path.
	macOSname="$(/bin/echo "$installerPath" | /usr/bin/sed 's/^\/Applications\/Install \(.*\)\.app$/\1/')"

	# Installer version.  Use parameter 5 in the Jamf Pro Server.
	# Command to get the installer version: `/usr/libexec/PlistBuddy -c 'Print :"System Image Info":version' "/Applications/Install macOS High Sierra.app/Contents/SharedSupport/InstallInfo.plist"
	# Ex: 10.13.6
	installerVersion="$5"
	if [[ -z $installerVersion ]]; then
		message 30 "The macOS installer version was not specified.  Please run \`/usr/libexec/PlistBuddy -c \'Print :\"System Image Info\":version\' \"/Applications/Install macOS High Sierra.app/Contents/SharedSupport/InstallerInfo.plist\"\` to get the installer version."
	elif [[ ! $installerVersion =~ ^[0-9]{2}\.?[0-9]{2}\.?[0-9]?$ ]]; then
		message 40 "The macOS installer version contained unknown an unknown value.  Exiting."
	fi
	[[ $debug == TRUE ]] && message 0 "The macOS installer version has been set to \"$installerVersion\"."
	installerVersionMajor="$(/bin/echo "$installerVersion" | /usr/bin/awk -F. '{print $2}')"
	installerVersionMinor="$(/bin/echo "$installerVersion" | /usr/bin/awk -F. '{print $3}')"

	# Download trigger.  This is the custom trigger on a Jamf Pro policy used to
	# manage the macOS installer download. This policy should only have a single
	# package (the macOS installer) and should not have any other scripts or
	# configuration. The policy should be set to ongoing with no other triggers
	# and should not have Self Service enabled. The only way this policy should
	# execute is by being called using this custom trigger.
	# Set the scope accordingly.
	downloadTrigger="$6"
	if [[ -z $downloadTrigger ]]; then
		message 50 "The download trigger was not specified."
	fi
	[[ $debug == TRUE ]] && message 0 "The download trigger was set to \"$downloadTrigger\"."

	# (OPTIONAL) md5 checksum of InstallESD.dmg
	# This optional value serves to validate the macOS installer.
	# Command to get the md5 checksum: `/sbin/md5 "/Applications/Install macOS High Sierra.app/Contents/SharedSupport/InstallESD.dmg"
	# Ex: b15b9db3a90f9ae8a9df0f812741e52ad
	installESDChecksum="$7"
	if [[ -z $installESDChecksum ]]; then
		[[ $debug == TRUE ]] && message 0 "(OPTIONAL) The md5 checksum was not set.  This setting will assume the download is valid if all other checks are valid."
	else
		[[ $debug == TRUE ]] && message 0 "(OPTIONAL) The md5 checksum has been set to \"$installESDChecksum\"."
	fi

	# Erase and Install Option. This instructs the installer to erase the local
	# hard drive before continuing with the macOS install.  This option is only
	# valid for macOS installer version 10.13.4 or later and macOS client
	# version 10.13 or later.
	eraseInstall="$8"
	if [[ -z $eraseInstall ]]; then
		message 0 "(OPTIONAL) The option to ERASE and install macOS was NOT selected.  The hard drive will not be wiped."
	elif [[ $eraseInstall =~ ^[01]$ ]]; then
		if ((eraseInstall == 0)); then
		message 0 "(OPTIONAL) The option to ERASE and install macOS was NOT selected."
		elif (( eraseInstall == 1 )); then
		message 0 "(OPTIONAL) The option to ERASE and install macOS WAS selected.  This will wipe the hard drive."
		fi
	else
		message 60 "The parameter for erase and install contained an unknown value.  Exiting."
	fi

	case $installerVersionMajor in
		13)
			minimumRAM="$minimumRAM1013"
			minimumSpace="$minimumSpace1013"
			;;
		14)
			minimumRAM="$minimumRAM1014"
			minimumSpace="$minimumSpace1014"
			;;
		*)
			message 90 "Unknown/Unsupported macOS installer version."
			;;
	esac

	checkFreeSpace "$minimumSpace" spaceStatus
	checkRAM "$minimumRAM" ramStatus
	checkPower powerStatus
	getFileVaultStatus fvStatus

	# downloadInstaller
	count=0
	successfulDownload=0

	while ((count < 3)); do
		if [[ -d "$installerPath" ]]; then
			message 0 "Found macOS installer.  Checking version."
			downloadVersion="$(/usr/libexec/PlistBuddy -c 'Print :"System Image Info":version' "$installerPath/Contents/SharedSupport/InstallInfo.plist")"
			if [[ $downloadVersion == "$installerVersion" ]]; then
				message 0 "macOS installer version matches.  Verifying checksum."
				verifyChecksum "$installerPath" "$installESDChecksum" validChecksum
			else
				message 0 "macOS installer found but version does not match."
				/bin/rm -rf "$installerPath"
				/bin/sleep 2
				downloadInstaller "$downloadTrigger"
			fi

			if ((validChecksum == 1)); then
				successfulDownload=1
				break
			fi
		else
			downloadInstaller "$downloadTrigger"
		fi

		successfulDownload=0
		((count++))
	done

	if ((successfulDownload == 0)); then
		windowType="utility"
		windowPosition="center"
		title="$macOSname Upgrade."
		heading="Error downloading $macOSname installer."
		description="There was an error preparing your computer for $macOSname.  The $macOSname installer did not download correctly.  Please contact the myTECH Helpdesk for assistance.
email: helpdesk@tntech.edu, phone: (931) 372-3975"
		alignDescription="left"
		alignHeading="center"
		button1Label="OK"

		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType "$windowType" -windowPosition "$windowPosition" -title "$title" -heading "$heading" -alignHeading "$alignHeading" -description "$description" -alignDescription "$alignDescription" -button1 "$button1Label" -defaultButton 1
		/bin/rm -rf "$installerPath"
		message 100 "macOS installer download attempted 3 times - Checksum is not valid."
	fi

	createFirstBootScript "$installerPath"
	createLaunchDaemonPlist
	createLaunchAgentFileVaultRebootPlist "$installerPath"

	checkPower powerStatus
	if [[ ! $powerStatus == "OK" || ! $spaceStatus == "OK" || ! $ramStatus == "OK" ]]; then
		/bin/rm -f /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
		/bin/rm -f /Library/LaunchDaemons/edu.tntech.finishOSInstall.plist
		/bin/rm -f /usr/local/tntech/finishOSInstall/finishOSInstall.sh

		windowType="utility"
		windowPosition="center"
		title="$macOSname Upgrade."
		heading="Error downloading $macOSname installer."
		description="There was an error preparing your computer for $macOSname.  One of the system requirements (HD Space, RAM, Power Status) was not met.  Please contact the myTECH Helpdesk for assistance.
email: helpdesk@tntech.edu, phone: (931) 372-3975"
		alignDescription="left"
		alignHeading="center"
		button1Label="OK"

		message 0 "Launching jamfHelper Dialog (Requirements Not Met)."
		/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType "$windowType" -windowPosition "$windowPosition" -title "$title" -heading "$heading" -alignHeading "$alignHeading" -description "$description" -alignDescription "$alignDescription" -button1 "$button1Label" -defaultButton 1

#		jamfHelperPID=$!
#/bin/kill "jamfHelperPID"
		message 510 "System requirements error: HD Space ($spaceStatus), RAM ($ramStatus), power ($powerStatus)."
	fi

	message 0 "Launching startosinstall."
	if [[ $fvStatus == "FileVault is On." && $loggedInUsername != "root" ]]; then
		message 0 "Loading com.apple.install.osinstallersetupd.plist with launchctl into ${loggedInUsername}'s gui context."
		/bin/launchctl bootstrap gui/"$loggedInUsername" /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
	fi

	message 0 "Launching jamfHelper to begin the macOS install process."
	windowType="fs"
	heading="Please wait as you computer is prepared for $macOSname."
	description="Preparation for $macOSname will take approximately 5-10 minutes.  Once completed, your computer will reboot and continue the installation."
	alignDescription="left"
	alignHeading="center"
	button1Label="OK"
	icon="$installerPath/Contents/Resources/InstallAssistant.icns"
	iconSize=100

	/Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType "$windowType" -heading "$heading" -description "$description" -icon "$icon" -iconSize "$iconSize" &

	jamfHelperPID=$!

	case "$installerVersionMajor" in
		14)
			if ((eraseInstall == 1)); then
				"$installerPath"/Contents/Resources/startosinstall --agreetolicense --nointeraction --eraseinstall --pidtosignal "$jamfHelperPID" >> "$log" &
			else
				"$installerPath"/Contents/Resources/startosinstall --agreetolicense --nointeraction --pidtosignal "$jamfHelperPID" >> "$log" &
			fi
			;;
		13)
			if ((eraseInstall == 1 && osVersionMajor == 13 && installerVersionMinor >= 4)); then
				"$installerPath"/Contents/Resources/startosinstall --applicationpath "$installerPath" --agreetolicense --nointeraction --eraseinstall --pidtosignal "$jamfHelperPID" >> "$log" &
			else # No erase install or not the right installer/client version
				"$installerPath"/Contents/Resources/startosinstall --applicationpath "$installerPath" --agreetolicense --nointeraction --pidtosignal "$jamfHelperPID" >> "$log" &
			fi
			;;
		*)
			message 90 "Unknown/Unsupported macOS installer version."
			;;
	esac
	/bin/sleep 3
}

[[ ! -d "$logDir" ]] && mkdir -p "$logDir"
[[ -e "$log" ]] && rm "$log"
ln -s "$logDate" "$log"
[[ $debug == TRUE ]] && message 0 "Mode: DEBUG"
message 0 "BEGIN: $log $date"
main "$@"
finish