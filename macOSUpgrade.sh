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
#	Version is: 2018/10/11 @ 2:00pm
#
#	- 2018/10/11 @ 2:00pm by Jeff Rippy | Tennessee Tech University
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
appDir="/Applications"
app="${appDir}/App"
AppVersionFile="${app}/Contents/Info.plist"
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
	local myMinimumSpace="$1"
	local mySpaceStatus=""

	# Get the current amount of free space available.
	myFreeSpace="$(/usr/sbin/diskutil info / | /usr/bin/awk -F'[()]' '/Free Space|Available Space/ {print $2}' | /usr/bin/sed -e 's/\ Bytes//')"
	if ((myFreeSpace < myMinimumSpace)); then
		message 300 "Disk Check: $mySpaceStatus - $myFreeSpace Detected.  This is below the minimum threshold of $myMinimumSpace required."
	else
		mySpaceStatus="OK"
		message 0 "Disk Check: $mySpaceStatus - $myFreeSpace Free Space Detected."
	fi

	eval "$2=\$mySpaceStatus"
}

function checkRAM()
{
	true
}

function checkPower()
{
	true
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
	local convertToAPFS=""
	local minimumSpace=""
	local minimumRAM=""
	local spaceStatus=""
	local ramStatus=""
	local powerStatus=""
	local requiredMinimumSpace=""

	# Caffeinate
	/usr/bin/caffeinate -dis &
	caffeinatePID=$!
	[[ $debug == TRUE ]] && message 0 "Disabling sleep during script.  Caffeinate PID is $caffeinatePID."

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

	# (Optional) APFS conversion option. APFS is Apple's new filesystem for
	# macOS 10.13 High Sierra and is enabled by default.  With High Sierra, you
	# can disable the conversion if you wish to stay with HFS+.
	# This is no longer an option with macOS 10.14 Mojave and will be ignored
	# on Mojave installs.
	convertToAPFS="$9"
	if [[ -z $convertToAPFS ]]; then
		message 0 "(OPTIONAL) The option to use APFS (default) has been selected."
	elif [[ $convertToAPFS =~ ^[01]$ ]]; then
		if ((convertToAPFS == 0 )); then
			if ((installerVersionMajor == 13)); then
				message 0 "(OPTIONAL) The option to NOT convert to APFS and stay with HFS+ has been selected."
			else
				message 70 "(OPTIONAL) The option to NOT convert to APFS and stay with HFS+ has been selected. However, the macOS installer version is macOS 10.14 and APFS is required. Stopping installation."
			fi
		else
			message 0 "(OPTIONAL) The option to use APFS (default) has been selected."
		fi
	else
		message 80 "The parameter for conversion to APFS contained an unknown value.  Exiting."
	fi

	case $installerVersionMajor in
		13)
			minimumRAM="$minimumRAM1013"
			minimumSpace="$minimumSpace1013"
			requiredMinimumSpace="requiredMinimumSpace1013"
			;;
		14)
			minimumRAM="$minimumRAM1014"
			minimumSpace="$minimumSpace1014"
			requiredMinimumSpace="requiredMinimumSpace1014"
			;;
		*)
			message 80 "Unknown macOS installer version."
			;;
	esac

	checkFreeSpace "$minimumSpace" spaceStatus
	checkRAM "$minimumRAM" ramStatus
	checkPower powerStatus
}

[[ ! -d "$logDir" ]] && mkdir -p "$logDir"
[[ -e "$log" ]] && rm "$log"
ln -s "$logDate" "$log"
[[ $debug == TRUE ]] && message 0 "Mode: DEBUG"
message 0 "BEGIN: $log $date"
main "$@"
finish



:<<COMMENT
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# USER VARIABLES
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

##Specify path to OS installer. Use Parameter 4 in the JSS, or specify here
##Example: /Applications/Install macOS High Sierra.app
OSInstaller="$4"

##Version of Installer OS. Use Parameter 5 in the JSS, or specify here.
##Example Command: /usr/libexec/PlistBuddy -c 'Print :"System Image Info":version' "/Applications/Install\ macOS\ High\ Sierra.app/Contents/SharedSupport/InstallInfo.plistr"
##Example: 10.12.5
version="$5"
versionMajor=$( /bin/echo "$version" | /usr/bin/awk -F. '{print $2}' )
versionMinor=$( /bin/echo "$version" | /usr/bin/awk -F. '{print $3}' )

##Custom Trigger used for download. Use Parameter 6 in the JSS, or specify here.
##This should match a custom trigger for a policy that contains just the 
##MacOS installer. Make sure that the policy is scoped properly
##to relevant computers and/or users, or else the custom trigger will
##not be picked up. Use a separate policy for the script itself.
##Example trigger name: download-sierra-install
download_trigger="$6"

##MD5 Checksum of InstallESD.dmg
##This variable is OPTIONAL
##Leave the variable BLANK if you do NOT want to verify the checksum (DEFAULT)
##Example Command: /sbin/md5 /Applications/Install\ macOS\ High\ Sierra.app/Contents/SharedSupport/InstallESD.dmg
##Example MD5 Checksum: b15b9db3a90f9ae8a9df0f81741efa2b
installESDChecksum="$7"

##Valid Checksum?  O (Default) for false, 1 for true.
validChecksum=0

##Unsuccessful Download?  0 (Default) for false, 1 for true.
unsuccessfulDownload=0

##Erase & Install macOS (Factory Defaults)
##Requires macOS Installer 10.13.4 or later
##Disabled by default
##Options: 0 = Disabled / 1 = Enabled
##Use Parameter 8 in the JSS.
eraseInstall="$8"
if [[ "${eraseInstall:=0}" != 1 ]]; then eraseInstall=0 ; fi
#macOS Installer 10.13.3 or ealier set 0 to it.
if [ "$versionMajor${versionMinor:=0}" -lt 134 ]; then
    eraseInstall=0
fi

##Enter 0 for Full Screen, 1 for Utility window (screenshots available on GitHub)
##Full Screen by default
##Use Parameter 9 in the JSS.
userDialog="$9"
if [[ ${userDialog:=0} != 1 ]]; then userDialog=0 ; fi

##Title of OS
##Example: macOS High Sierra
macOSname=$(/bin/echo "$OSInstaller" | /usr/bin/sed 's/^\/Applications\/Install \(.*\)\.app$/\1/')

##Title to be used for userDialog (only applies to Utility Window)
title="$macOSname Upgrade"

##Heading to be used for userDialog
heading="Please wait as we prepare your computer for $macOSname..."

##Title to be used for userDialog
description="This process will take approximately 5-10 minutes.
Once completed your computer will reboot and begin the upgrade."

##Description to be used prior to downloading the OS installer
dldescription="We need to download $macOSname to your computer, this will \
take several minutes."

##Jamf Helper HUD Position if macOS Installer needs to be downloaded
##Options: ul (Upper Left); ll (Lower Left); ur (Upper Right); lr (Lower Right)
##Leave this variable empty for HUD to be centered on main screen
dlPosition="ul"

##Icon to be used for userDialog
##Default is macOS Installer logo which is included in the staged installer package
icon="$OSInstaller/Contents/Resources/InstallAssistant.icns"

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# FUNCTIONS
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

downloadInstaller() {
    /bin/echo "Downloading macOS Installer..."
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
        -windowType hud -windowPosition $dlPosition -title "$title" -alignHeading center -alignDescription left -description "$dldescription" \
        -lockHUD -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarDownloadsFolder.icns" -iconSize 100 &
    ##Capture PID for Jamf Helper HUD
    jamfHUDPID=$!
    ##Run policy to cache installer
    /usr/local/jamf/bin/jamf policy -event "$download_trigger"
    ##Kill Jamf Helper HUD post download
    /bin/kill "${jamfHUDPID}"
}

verifyChecksum() {
    if [[ "$installESDChecksum" != "" ]]; then
        osChecksum=$( /sbin/md5 -q "$OSInstaller/Contents/SharedSupport/InstallESD.dmg" )
        if [[ "$osChecksum" == "$installESDChecksum" ]]; then
            /bin/echo "Checksum: Valid"
            validChecksum=1
            return
        else
            /bin/echo "Checksum: Not Valid"
            /bin/echo "Beginning new dowload of installer"
            /bin/rm -rf "$OSInstaller"
            /bin/sleep 2
            downloadInstaller
        fi
    else
        ##Checksum not specified as script argument, assume true
        validChecksum=1
        return
    fi
}

cleanExit() {
    /bin/kill "${caffeinatePID}"
    exit "$1"
}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# SYSTEM CHECKS
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

##Caffeinate
/usr/bin/caffeinate -dis &
caffeinatePID=$!

##Get Current User
currentUser=$( /usr/bin/stat -f %Su /dev/console )

##Check if FileVault Enabled
fvStatus=$( /usr/bin/fdesetup status | head -1 )

##Check if device is on battery or ac power
pwrAdapter=$( /usr/bin/pmset -g ps )
if [[ ${pwrAdapter} == *"AC Power"* ]]; then
    pwrStatus="OK"
    /bin/echo "Power Check: OK - AC Power Detected"
else
    pwrStatus="ERROR"
    /bin/echo "Power Check: ERROR - No AC Power Detected"
fi

##Check if free space > 15GB
osMajor=$( /usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{print $2}' )
osMinor=$( /usr/bin/sw_vers -productVersion | /usr/bin/awk -F. '{print $3}' )
if [[ $osMajor -eq 12 ]] || [[ $osMajor -eq 13 && $osMinor -lt 4 ]]; then
    freeSpace=$( /usr/sbin/diskutil info / | /usr/bin/grep "Available Space" | /usr/bin/awk '{print $6}' | /usr/bin/cut -c 2- )
else
    freeSpace=$( /usr/sbin/diskutil info / | /usr/bin/grep "Free Space" | /usr/bin/awk '{print $6}' | /usr/bin/cut -c 2- )
fi

if [[ ${freeSpace%.*} -ge 15000000000 ]]; then
    spaceStatus="OK"
    /bin/echo "Disk Check: OK - ${freeSpace%.*} Bytes Free Space Detected"
else
    spaceStatus="ERROR"
    /bin/echo "Disk Check: ERROR - ${freeSpace%.*} Bytes Free Space Detected"
fi

##Check for existing OS installer
loopCount=0
while [[ $loopCount -lt 3 ]]; do
    if [ -e "$OSInstaller" ]; then
        /bin/echo "$OSInstaller found, checking version."
        OSVersion=$(/usr/libexec/PlistBuddy -c 'Print :"System Image Info":version' "$OSInstaller/Contents/SharedSupport/InstallInfo.plist")
        /bin/echo "OSVersion is $OSVersion"
        if [ "$OSVersion" = "$version" ]; then
          /bin/echo "Installer found, version matches. Verifying checksum..."
          verifyChecksum
        else
          ##Delete old version.
          /bin/echo "Installer found, but old. Deleting..."
          /bin/rm -rf "$OSInstaller"
          /bin/sleep 2
          downloadInstaller
        fi
        if [ "$validChecksum" == 1 ]; then
            unsuccessfulDownload=0
            break
        fi
    else
        downloadInstaller
    fi

    unsuccessfulDownload=1
    ((loopCount++))
done

if (( unsuccessfulDownload == 1 )); then
    /bin/echo "macOS Installer Downloaded 3 Times - Checksum is Not Valid"
    /bin/echo "Prompting user for error and exiting..."
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$icon" -heading "Error Downloading $macOSname" -description "We were unable to prepare your computer for $macOSname. Please contact the IT Support Center." -iconSize 100 -button1 "OK" -defaultButton 1
    cleanExit 0
fi


# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# CREATE FIRST BOOT SCRIPT
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

/bin/mkdir -p /usr/local/jamfps

/bin/echo "#!/bin/bash
## First Run Script to remove the installer.
## Clean up files
/bin/rm -fr \"$OSInstaller\"
/bin/sleep 2
## Update Device Inventory
/usr/local/jamf/bin/jamf recon
## Remove LaunchDaemon
/bin/rm -f /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist
## Remove Script
/bin/rm -fr /usr/local/jamfps
exit 0" > /usr/local/jamfps/finishOSInstall.sh

/usr/sbin/chown root:admin /usr/local/jamfps/finishOSInstall.sh
/bin/chmod 755 /usr/local/jamfps/finishOSInstall.sh

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# LAUNCH DAEMON
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

/bin/cat << EOF > /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.jamfps.cleanupOSInstall</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>/usr/local/jamfps/finishOSInstall.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

##Set the permission on the file just made.
/usr/sbin/chown root:wheel /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist
/bin/chmod 644 /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# LAUNCH AGENT FOR FILEVAULT AUTHENTICATED REBOOTS
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

##Determine Program Argument
if [[ $osMajor -ge 11 ]]; then
    progArgument="osinstallersetupd"
elif [[ $osMajor -eq 10 ]]; then
    progArgument="osinstallersetupplaind"
fi

/bin/cat << EOP > /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
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
EOP

##Set the permission on the file just made.
/usr/sbin/chown root:wheel /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
/bin/chmod 644 /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# APPLICATION
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

if [[ ${pwrStatus} == "OK" ]] && [[ ${spaceStatus} == "OK" ]]; then
    ##Launch jamfHelper
    if [ ${userDialog} -eq 0 ]; then
        /bin/echo "Launching jamfHelper as FullScreen..."
        /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType fs -title "" -icon "$icon" -heading "$heading" -description "$description" &
        jamfHelperPID=$!
    else
        /bin/echo "Launching jamfHelper as Utility Window..."
        /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$icon" -heading "$heading" -description "$description" -iconSize 100 &
        jamfHelperPID=$!
    fi
    ##Load LaunchAgent
    if [[ ${fvStatus} == "FileVault is On." ]] && [[ ${currentUser} != "root" ]]; then
        userID=$( /usr/bin/id -u "${currentUser}" )
        /bin/launchctl bootstrap gui/"${userID}" /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
    fi
    ##Begin Upgrade
    /bin/echo "Launching startosinstall..."
    ##Check if eraseInstall is Enabled
    if [[ $eraseInstall == 1 ]]; then
        eraseopt='--eraseinstall'
        /bin/echo "   Script is configured for Erase and Install of macOS."
    fi

    osinstallLogfile="/var/log/startosinstall.log"
    if [ "$versionMajor" -ge 14 ]; then
        eval /usr/bin/nohup "\"$OSInstaller/Contents/Resources/startosinstall\"" "$eraseopt" --agreetolicense --nointeraction --pidtosignal "$jamfHelperPID" >> "$osinstallLogfile" &
    else
        eval /usr/bin/nohup "\"$OSInstaller/Contents/Resources/startosinstall\"" "$eraseopt" --applicationpath "\"$OSInstaller\"" --agreetolicense --nointeraction --pidtosignal "$jamfHelperPID" >> "$osinstallLogfile" &
    fi
    /bin/sleep 3
else
    ## Remove Script
    /bin/rm -f /usr/local/jamfps/finishOSInstall.sh
    /bin/rm -f /Library/LaunchDaemons/com.jamfps.cleanupOSInstall.plist
    /bin/rm -f /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist

    /bin/echo "Launching jamfHelper Dialog (Requirements Not Met)..."
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper -windowType utility -title "$title" -icon "$icon" -heading "Requirements Not Met" -description "We were unable to prepare your computer for $macOSname. Please ensure you are connected to power and that you have at least 15GB of Free Space.

    If you continue to experience this issue, please contact the IT Support Center." -iconSize 100 -button1 "OK" -defaultButton 1

fi

cleanExit 0
COMMENT