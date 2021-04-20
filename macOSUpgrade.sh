#!/bin/bash

################################################################################
#
#  Copyright (c) 2020, Jamf.  All rights reserved.
#
#    Redistribution and use in source and binary forms, with or without
#    modification, are permitted provided that the following conditions
#    are met:
#      * Redistribution of source code must retain the above copyright
#        notice, this list of conditions and the following disclaimer.
#      * Redistributions in binary form must reproduce the above copyright
#        notice, this list of conditions and the following disclaimer in the
#        documentation and/or other materials provided with the distribution.
#      * Neither the name of the Jamf nor the names of its contributors
#        may be used to endorse or promote products derived from this
#        software without specific prior written permission.
#
#    THIS SOFTWARE IS PROVIDED BY JAMF SOFTWARE, LLC "AS IS" AND ANY
#    EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#    IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
#    PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL JAMF SOFTWARE, LLC BE LIABLE
#    FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
#    CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
#    SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
#    INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#    CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
#    ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
#    THE POSSIBILITY OF SUCH DAMAGE.
#
################################################################################
#
#  This script was designed to be used in a Self Service policy to ensure
#  specific requirements have been met before proceeding with an inplace upgrade
#  of the macOS, as well as to address changes Apple has made to the ability to
#  complete macOS upgrades silently.
#
#  REQUIREMENTS:
#    - Jamf Pro
#    - macOS Clients running version 10.10.5 or later
#    - macOS Installer 10.12.4 or later
#    - eraseInstall option is ONLY supported with macOS Installer 10.13.4+
#      and client-side macOS 10.13+
#    - Look over the USER VARIABLES and configure as needed.
#
#  For more information, visit https://github.com/kc9wwh/macOSUpgrade
#  Written by: Joshua Roskos | Jamf
################################################################################
#
#  The copyright notice is left in place as this was originally written by Jamf.
#  It has been heavily modified for TNTech use.
#
################################################################################

# Begin TNTech Code
################################################################################
#
#	ABOUT THIS PROGRAM
#
#	NAME
#		macOSUpgrade.sh
#
################################################################################
#
#	HISTORY
#
#	Version is: YYYY/MM/DD @ HH:MMam/pm
#	Version is: 2021/04/20 @ 5:00pm
#
#  - 2021/04/20 @ 5:00pm by Jeff Rippy | Tennessee Tech University
#    - Updated to merge changes from Joshua's Master Branch.
#    - Modified script to abide by Google's Bash Shell Style Guide
#    - https://google.github.io/styleguide/shellguide.html#s5-formatting
#  - 2019/10/31 @ 12:00pm by Jeff Rippy | Tennessee Tech University
#    - Updated to reflect some changes from Joshua's Master Branch.
#    - Last commit at this time is 5790877 on 2019/07/15
#  - 2018/10/19 @ 2:00pm by Jeff Rippy | Tennessee Tech University
#    - Updated to reflect some changes from Joshua's Master Branch.
#    - v. 2.7.2.1
#  - 2018/09/28 by Joshua Roskos | Jamf
#    - Incorporated several commits on Github.
#    - Version incremented to 2.7.2.1
#  - 2018/09/18 @ 4:30pm by Jeff Rippy | Tennessee Tech University
#    - Forked from Joshua Roskos original project and modified for
#      Tennessee Tech
#    - Github source: https://github.com/scifiman/macOSUpgrade
#  - 2017/01/05 by Joshua Roskos | Jamf
#    - Initial Script
#    - Github source: https://github.com/kc9wwh/macOSUpgrade
# 
################################################################################
#
#	DEFINE VARIABLES & READ IN PARAMETERS
#
################################################################################

readonly SCRIPT_NAME="macOS Upgrade"
DATE="$(date "+%Y%m%d.%H%M.%S")"
readonly DATE
readonly DEBUG="TRUE"
readonly LOG_DIR="/tmp/${SCRIPT_NAME}"
readonly LOG="${LOG_DIR}/${SCRIPT_NAME}.log"
readonly LOG_DATE="${LOG_DIR}/${SCRIPT_NAME}.log.${DATE}"
readonly OS_INSTALL_LOG="/var/log/startosinstall.log"
#SERIAL_NUMBER="$(/usr/sbin/ioreg -l \
#  | /usr/bin/grep -i ioplatformserialnumber \
#  | /usr/bin/awk -F "= " '{print $2}' \
#  | /usr/bin/sed -e 's/"//g')"
#readonly SERIAL_NUMBER
CAFFEINATE_PID=""
COMPUTER_NAME=""
LOGGED_IN_USERNAME=""
MOUNT_POINT=""
#APP_DIR="/Applications"
#APP="${APP_DIR}/App"
#APP_VERSION_FILE="${APP}/Contents/Info.plist"
OS_VERSION="$(/usr/bin/sw_vers -productVersion)"
OS_VERSION_BASE="$(/bin/echo "${OS_VERSION}" | /usr/bin/awk -F. '{print $1}')"
OS_VERSION_MAJOR="$(/bin/echo "${OS_VERSION}" | /usr/bin/awk -F. '{print $2}')"
PREVIOUS_PROCESSES=("caffeinate" "startosinstall" "osinstallersetupd")
TEMP_PROCESS=""
#OS_VERSION_MINOR="$(/bin/echo "${OS_VERSION}" | /usr/bin/awk -F. '{print $3}')"
GIGABYTES=$((1000 ** 3))
GIBIBYTES=$((1024 ** 3))
MACOS_NAME=""
WAIT_TIME=5  # Time in minutes.
WAIT_TIME_FOR_AC=$((60 * WAIT_TIME))
FINISH_OS_SCRIPT_DIR="/usr/local/tntech/finish_os_install"
FINISH_OS_SCRIPT_NAME="finish_os_install.sh"
FINISH_OS_SCRIPT_PATH="${FINISH_OS_SCRIPT_DIR}/${FINISH_OS_SCRIPT_NAME}"
FIRST_BOOT_SCRIPT_NAME="first_boot_upgrade.log"
FIRST_BOOT_SCRIPT_PATH="${FINISH_OS_SCRIPT_DIR}/${FIRST_BOOT_SCRIPT_NAME}"
LAUNCH_DAEMON_NAME="edu.tntech.cleanupOSInstall"
LAUNCH_DAEMON_SETTINGS_PATH="/Library/LaunchDaemons/${LAUNCH_DAEMON_NAME}.plist"
LAUNCH_AGENT_NAME="com.apple.install.osinstallersetupd"
LAUNCH_AGENT_SETTINGS_PATH="/Library/LaunchAgents/${LAUNCH_AGENT_NAME}.plist"

ERROR_ICON_PATH="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertStopIcon.icns"
WARNING_ICON_PATH_PRE_BIG_SUR="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionIcon.icns"
WARNING_ICON_PATH_BIG_SUR="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/AlertCautionBadgeIcon.icns"

# Minimum requirements for install.  These are my required minimums for
# Tennessee Tech.
# Actual system requirements Mojave: https://support.apple.com/en-us/HT201475
# Actual system requirements Catalina: https://support.apple.com/en-us/HT210222
# Actual system requirements Big Sur: https://support.apple.com/en-us/HT211238
REQUIRED_MINIMUM_RAM_1013=4
REQUIRED_MINIMUM_RAM_1014=4
REQUIRED_MINIMUM_RAM_1015=4
REQUIRED_MINIMUM_RAM_110=4
REQUIRED_MINIMUM_STORAGE_1013=15
REQUIRED_MINIMUM_STORAGE_1014=20
REQUIRED_MINIMUM_STORAGE_1015=20
REQUIRED_MINIMUM_STORAGE_110=48

################################################################################
#
#  SCRIPT CONTENTS - DO NOT MODIFY BELOW THIS LINE
#
################################################################################

################################################################################
#  Kill running process
#  Globals:
#    None
#  Arguments:
#    process_id
#  Locals:
#    process_id
#  Returns:
#    None
################################################################################
function kill_process()
{
  local process_id="$1"

  if /bin/ps -p "${process_id}" > /dev/null; then
    /bin/kill "${process_id}"
    wait "${process_id}" 2>/dev/null
  fi
}

################################################################################
#  Finish this script and terminate
#  Globals:
#    CAFFEINATE_PID
#    LOG
#  Arguments:
#    exit_status
#  Locals:
#    exit_status
#  Returns:
#    None
################################################################################
function finish()
{
  local exit_status="$1"
  if [[ -z "${exit_status}" ]]; then
    exit_status=0
  fi

  if [[ -n "${CAFFEINATE_PID}" ]]; then
    if [[ "${DEBUG}" == "TRUE" ]]; then
      message 0 "Stopping caffeinate PID: ${CAFFEINATE_PID}."
    fi

    kill_process "${CAFFEINATE_PID}"
  fi

  /bin/echo "FINISH: ${LOG}" | /usr/bin/tee -a "${LOG}"
  /usr/bin/logger -f "${LOG}"
  exit "${exit_status}"
}

################################################################################
#  Formats a warning message for stdout and log output.
#  Globals:
#    LOG
#  Arguments:
#    code
#    message
#  Locals:
#    code
#    message
#  Returns:
#    None
################################################################################
function warning_message()
{
  local code="$1"
  local message="$2"
  if [[ -z "${message}" ]]; then
    message="Unknown Warning"
  fi
  /bin/echo "WARNING: (${code}) ${message}" | /usr/bin/tee -a "${LOG}"
}

################################################################################
#  Formats a normal message for stdout and log output.
#  Globals:
#    LOG
#  Arguments:
#    message
#  Locals:
#    message
#  Returns:
#    None
################################################################################
function normal_message()
{
  local message="$1"
  if [[ -z "${message}" ]]; then
    return
  fi
  /bin/echo "${message}" | /usr/bin/tee -a "${LOG}"
}

################################################################################
#  Formats an error message for stdout and log output.
#  Globals:
#    LOG
#  Arguments:
#    code
#    message
#  Locals:
#    code
#    message
#  Returns:
#    None
################################################################################
function error_message()
{
  local code="$1"
  local message="$2"
  /bin/echo "ERROR: (${code}) ${message}" | /usr/bin/tee -a "${LOG}"
  finish "${code}"
}

################################################################################
#  Accepts a message.  Performs checking and calls the appropriate helper.
#  Globals:
#    LOG
#  Arguments:
#    code
#    message
#  Locals:
#    code
#    message
#  Returns:
#    None
################################################################################
function message()
{
  local code="$1"
  local message="$2"
	
  if (( code > 0 )); then
    error_message "${code}" "${message}"
  elif (( code < 0 )); then
    warning_message "${code}" "${message}"
  elif (( code == 0 )); then
    normal_message "${message}"
  else
    error_message "${code}" "Unknown Error Code"
  fi
}

################################################################################
#  Verifies the Checksum of the Installer
#  Globals:
#    OS_VERSION_BASE
#  Arguments:
#    _retval
#    my_checksum
#    my_installer_path
#  Locals:
#    _retval
#    my_checksum
#    my_checksum_status
#    my_installer_checksum
#    my_installer_dmg_path
#    my_installer_path
#  Returns:
#    _retval
#  Error code range: 100-119
################################################################################
function check_checksum()
{
  local _retval="$3"
  local my_installer_path="$1"
  local my_installer_checksum="$2"
  local my_checksum=""
  local my_checksum_status="ERROR"
  local my_installer_dmg_path=""

  case "${OS_VERSION_BASE}" in
    11)
          my_installer_dmg_path="${my_installer_path}/Contents/SharedSupport/SharedSupport.dmg"
      ;;
    10)
      my_installer_dmg_path="${my_installer_path}/Contents/SharedSupport/InstallESD.dmg"
      ;;
  esac
  
  my_checksum="$(/sbin/md5 -q "${my_installer_dmg_path}")"
  if [[ "${my_checksum}" != "${my_installer_checksum}" ]]; then
    if [[ "${DEBUG}" == "TRUE" ]]; then
      message 0 "Checksum of ${my_installer_dmg_path} is: \"${my_checksum}\"."
    fi
    my_checksum_status="ERROR"
    message -100 "Checksum status is ${my_checksum_status}.  macOS Installer could not be verified."
  else
    my_checksum_status="OK"
    message 0 "Checksum status is ${my_checksum_status}.  Installer checksum matches given checksum."
  fi

  eval "${_retval}=\${my_checksum_status}"
}

################################################################################
#  Verifies FileVault Status
#  Globals:
#    ERROR_ICON_PATH
#  Arguments:
#    _retval
#    _retval2
#  Locals:
#    _retval
#    _retval2
#    my_complete_fv_status
#    my_fv_status
#  Returns:
#    _retval
#  Error code range: 120-139
################################################################################
function check_filevault()
{
  local _retval="$1"
  local _retval2="$2"
  local my_complete_fv_status=""
  local my_fv_status="ERROR"

  my_complete_fv_status="$(/usr/bin/fdesetup status | /usr/bin/head -1)"
  message 0 "FileVault Check: ${my_complete_fv_status}"

  if [[ "${my_complete_fv_status}" != "FileVault is On." ]] && [[ "${my_complete_fv_status}" != "FileVault is Off." ]]; then
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
      -windowType utility \
      -title "System Requirements Error (FileVault)" \
      -description "There was a problem verifying your system requirements.  Please contact your ITS representative to resolve this issue.  FileVault must not be in the process of encrypting or decrypting during installation attempt." \
      -button1 "OK" \
      -defaultButton 1 \
      -timeout 600 \
      -icon "${ERROR_ICON_PATH}" \
      -iconSize 250 &

    message 120 "Cannot proceed while FileVault is encrypting or decrypting.  Wait for current operation to finish before trying again.  Status: \"${my_fv_status} - ${my_complete_fv_status}\"."
  else
    my_fv_status="OK"
  fi

  eval "${_retval}=\${my_fv_status}"
  eval "${_retval2}=\${my_complete_fv_status}"
}

################################################################################
#  Verifies amount of free storage available
#  Globals:
#    ERROR_ICON_PATH
#    GIGABYTES
#    OS_VERSION
#    OS_VERSION_BASE
#    OS_VERSION_MAJOR
#  Arguments:
#    _retval
#    my_installer_path
#    my_minimum_storage_bytes
#  Locals:
#    _retval
#    my_disk_info_plist
#    my_free_storage
#    my_free_storage_bytes
#    my_install_size_bytes
#    my_installer_path
#    my_minimum_storage
#    my_storage_status
#  Returns:
#    _retval
#  Error code range: 140-159
################################################################################
function check_free_storage()
{
  local _retval="$3"
  local my_minimum_storage="$1"
  local my_install_size_bytes="0"
  local my_installer_path="$2"
  local my_free_storage=""
  local my_free_storage_bytes=""
  local my_disk_info_plist=""
  local my_storage_status="ERROR"

  # Get the size of the installer if it already exists.
  if [[ -e "${my_installer_path}" ]]; then
    my_install_size_bytes="$(/usr/bin/du -s "${my_installer_path}" | /usr/bin/awk '{print $1}')"
  fi

  # With 10.15.0 and later, it is part of APFS: APFSContainerFree.
  # Previous version use FreeSpace
  my_disk_info_plist="$(/usr/sbin/diskutil info -plist /)"

  case "${OS_VERSION_BASE}" in
    11)
      my_free_storage_bytes="$(/usr/libexec/PlistBuddy -c "Print :APFSContainerFree" /dev/stdin <<< "${my_disk_info_plist}" 2>/dev/null)"
      ;;
    10)
      case "${OS_VERSION_MAJOR}" in
        15)
          my_free_storage_bytes="$(/usr/libexec/PlistBuddy -c "Print :APFSContainerFree" /dev/stdin <<< "${my_disk_info_plist}" 2>/dev/null)"
          ;;
        14|13|12|11)
          my_free_storage_bytes="$(/usr/libexec/PlistBuddy -c "Print :FreeSpace" dev/stdin <<< "${my_disk_info_plist}" 2>/dev/null)"
          ;;
        *)
          message 141 "Unknown OS or OS out of date: ${OS_VERSION}."
          ;;
      esac
      ;;
    *)
      message 140 "Unknown OS or OS out of date: ${OS_VERSION}."
      ;;
  esac

  my_free_storage_bytes="$((my_free_storage_bytes + my_install_size_bytes))"
  my_free_storage="$((my_free_storage_bytes / GIGABYTES))"

  if ((my_free_storage >= my_minimum_storage )); then
      my_storage_status="OK"
      message 0 "Storage Check: ${my_storage_status} - Adequate storage storage detected: ${my_free_storage} GB.  Required: ${my_minimum_storage} GB."
  else
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
      -windowType utility \
      -title "System Requirements Error (Storage)" \
      -description "There was a problem verifying your system requirements.  Please contact your ITS representative to resolve this issue.  Insufficient storage space to proceed with installation.  Avaiable space: ${my_free_storage} GB." \
      -button1 "OK" \
      -defaultButton 1 \
      -timeout 600 \
      -icon "${ERROR_ICON_PATH}" \
      -iconSize 250 &

    message 142 "Storage Check: ${my_storage_status} - Insufficient storage " \
      "storage: ${my_free_storage} GB.  Required: ${my_minimum_storage} GB."
  fi

  eval "${_retval}=\${my_storage_status}"
}

################################################################################
#  Verifies AC power connected to computer
#  Globals:
#    DEBUG
#    ERROR_ICON_PATH
#    WAIT_TIME_FOR_AC
#    WARNING_ICON_PATH
#  Arguments:
#    _retval
#  Locals:
#    _retval
#    my_count
#    my_jamfHelper_PID
#    my_power_status
#  Returns:
#    _retval
#  Error code range: 160-179
################################################################################
function check_power()
{
  local _retval="$1"
  local my_count=0
  local my_jamfHelper_pid=""
  local my_power_status="ERROR"

  if /usr/bin/pmset -g ps | grep "AC Power" > /dev/null; then
    my_power_status="OK"
    message 0 "Power Check: ${my_power_status} - AC power detected."
    eval "${_retval}=\${my_power_status}"
    return
  else
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
      -windowType utility \
      -title "System Requirements Warning (Power)" \
      -description "Please connect your computer to AC Power to continue." \
      -icon "${WARNING_ICON_PATH}" \
      -iconSize 250 &
    my_jamfHelper_pid=$!
  fi

  while ((my_count < WAIT_TIME_FOR_AC))
  do
    if /usr/bin/pmset -g ps | grep "AC Power" > /dev/null; then
      my_power_status="OK"
      message 0 "Power Check: ${my_power_status} - AC power detected."
      eval "${_retval}=\${my_power_status}"
      kill_process "${my_jamfHelper_pid}"
      return
    else
      my_power_status="ERROR"
      if [[ "${DEBUG}" == "TRUE" ]]; then
        message 0 "(${my_count}) Power Check: ${my_power_status} - No AC power detected."
      fi
    fi
    /bin/sleep 1
    ((my_count++))
  done

  kill_process "${my_jamfHelper_pid}"
  if [[ "${my_power_status}" != "OK" ]]; then
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
      -windowType utility \
      -title "System Requirements Error (Power)" \
      -description "There was a problem verifying your system requirements.  Please contact your ITS representative to resolve this issue.  AC power not connected during installation attempt." \
      -button1 "OK" \
      -defaultButton 1 \
      -timeout 600 \
      -icon "${ERROR_ICON_PATH}" \
      -iconSize 250 &

    message 160 "AC Power not connected.  Cannot proceed with installation."
  fi
}

################################################################################
#  Verifies amount of RAM
#  Globals:
#    ERROR_ICON_PATH
#    GIBIBYTES
#  Arguments:
#    _retval
#    my_minimum_ram
#  Locals:
#    _retval
#    my_installed_ram
#    my_installed_ram_bytes
#    my_minimum_ram
#    my_ram_status
#  Returns:
#    _retval
#  Error code range: 180-199
################################################################################
function check_ram()
{
  local _retval="$2"
  local my_installed_ram=""
  local my_installed_ram_bytes=""
  local my_minimum_ram="$1"
  local my_ram_status="ERROR"

  # Get the current amount of installed RAM.
  my_installed_ram_bytes="$(/usr/sbin/sysctl -n hw.memsize)"
  my_installed_ram="$((my_installed_ram_bytes / GIBIBYTES))"

  if ((my_installed_ram >= my_minimum_ram)); then
    my_ram_status="OK"
    message 0 "RAM Check: ${my_ram_status} - Adequate RAM detected: ${my_installed_ram} GiB.  Required: ${my_minimum_ram} GiB."
  else
    my_ram_status="ERROR"
    
    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
      -windowType utility \
      -title "System Requirements Error (RAM)" \
      -description "There was a problem verifying your system requirements.  Please contact your ITS representative to resolve this issue.  Insufficient RAM." \
      -button1 "OK" \
      -defaultButton 1 \
      -timeout 600 \
      -icon "${ERROR_ICON_PATH}" \
      -iconSize 250 &
    
    message 180 "RAM Check: ${my_ram_status} - Insufficient RAM detected. ${my_installed_ram} GiB.  Required: ${my_minimum_ram} GiB."
  fi

  eval "${_retval}=\${my_ram_status}"
}

################################################################################
#  Clean up install files
#  Globals:
#    FINISH_OS_SCRIPT_PATH
#    LAUNCH_AGENT_SETTINGS_PATH
#    LAUNCH_DAEMON_SETTINGS_PATH
#  Arguments:
#    None
#  Locals:
#    my_file
#    my_files_to_remove
#  Returns:
#    None
#  Error code range: 200-219
################################################################################
function clean_up_install_files()
{
  # Remove LaunchAgent and LaunchDaemon
  local my_file=""
  local my_files_to_remove=( "${LAUNCH_AGENT_SETTINGS_PATH}" "${LAUNCH_DAEMON_SETTINGS_PATH}" "${FINISH_OS_SCRIPT_PATH}" )

  for my_file in "${my_files_to_remove[@]}"; do
    if [[ -e "${my_file}" ]]; then
      message 0 "Removing file ${my_file}."
      /bin/rm -f "${my_file}"
    fi
  done
}

################################################################################
#  Create boot script
#  Globals:
#    FINISH_OS_SCRIPT_DIR
#    FINISH_OS_SCRIPT_PATH
#    FIRST_BOOT_SCRIPT_PATH
#  Arguments:
#    my_installer_path
#  Locals:
#    my_installer_path
#  Returns:
#    None
#  Error code range: 220-239
################################################################################
function create_first_boot_script()
{
  local my_installer_path="$1"
  /bin/mkdir -p "${FINISH_OS_SCRIPT_DIR}"

  # Inside of a HEREDOC section inside a script, escape variables to avoid
  # evaluating the variables inside the parent script.
  /bin/cat << EOF > "${FINISH_OS_SCRIPT_PATH}"
#!/bin/bash
# First run script to remove the installer and associated files.
installer_progress_process=""

# Wait for .AppleUpgrade to be deleted.
while [[ -e /var/db/.AppleUpgrade ]]; do
  echo "\$(date "+%a %h %d %H:%M:%S"): Waiting for /var/db/.AppleUpgrade to disappear." >> "${FIRST_BOOT_SCRIPT_PATH}"
  /bin/sleep 60
done

# Wait until the upgrade process completes
installer_progress_process=\$(pgrep -l "Installer Progress")
until [[ "\${installer_progress_process}" == "" ]]; do
  echo "\$(date "+%a %h %d %H:%M:%S"): Waiting for Installer Progress to complete." >> "${FIRST_BOOT_SCRIPT_PATH}"
  /bin/sleep 60
  installer_progress_process=\$(pgrep -l "Installer Progress")
done

# Clean up files
/bin/rm -rf "$my_installer_path"
/bin/sleep 2

# Update inventory
/usr/local/jamf/bin/jamf recon

# Remove LaunchAgent and LaunchDaemon
/bin/rm -f "${LAUNCH_AGENT_SETTINGS_PATH}"
/bin/rm -f "${LAUNCH_DAEMON_SETTINGS_PATH}"

# Remove this script
/bin/rm -f "${FINISH_OS_SCRIPT_PATH}"
exit 0
EOF

  /usr/sbin/chown -R root:admin "${FINISH_OS_SCRIPT_DIR}"
  /bin/chmod -R 755 "${FINISH_OS_SCRIPT_DIR}"
  message 0 "First Boot Script successfully created at ${FINISH_OS_SCRIPT_DIR}."
}

################################################################################
# Create LaunchAgent for FileVault Authenticated Reboots
#  Globals:
#    None
#  Arguments:
#    my_installer_path
#  Locals:
#    my_installer_path
#  Returns:
#    None
#  Error code range: 240-259
################################################################################
function create_launch_agent_filevault_reboot_plist()
{
  local my_installer_path="$1"

  /bin/cat << EOF > "${LAUNCH_AGENT_SETTINGS_PATH}"
<?xml version="1.0" encoding="UTF-8" ?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${LAUNCH_AGENT_NAME}</string>
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>MachServices</key>
	<dict>
		<key>${LAUNCH_AGENT_NAME}</key>
		<true/>
	</dict>
	<key>TimeOut</key>
	<integer>300</integer>
	<key>OnDemand</key>
	<true/>
	<key>ProgramArguments</key>
	<array>
		<string>${my_installer_path}/Contents/Frameworks/OSInstallerSetup.framework/Resources/osinstallersetupd</string>
	</array>
</dict>
</plist>
EOF

  /usr/sbin/chown root:wheel "${LAUNCH_AGENT_SETTINGS_PATH}"
  /bin/chmod 644 "${LAUNCH_AGENT_SETTINGS_PATH}"
  message 0 "LaunchAgent for FileVault Reboot successfully created at ${LAUNCH_AGENT_SETTINGS_PATH}."
}

################################################################################
#  Create LaunchDaemon
#  Globals:
#    FINISH_OS_SCRIPT_PATH
#    LAUNCH_DAEMON_NAME
#    LAUNCH_DAEMON_SETTINGS_PATH
#  Arguments:
#    None
#  Locals:
#    None
#  Returns:
#    None
#  Error code range: 260-279
################################################################################
function create_launch_daemon_plist()
{
  # Inside of a HEREDOC section inside a script, escape variables to avoid
  # evaluating the variables inside the parent script.
  /bin/cat << EOF > "${LAUNCH_DAEMON_SETTINGS_PATH}"
<?xml version="1.0" encoding="UTF-8" ?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LAUNCH_DAEMON_NAME}</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>-c</string>
		<string>${FINISH_OS_SCRIPT_PATH} </string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
EOF

  /usr/sbin/chown root:wheel "${LAUNCH_DAEMON_SETTINGS_PATH}"
  /bin/chmod 644 "${LAUNCH_DAEMON_SETTINGS_PATH}"
  message 0 "LaunchDaemon successfully created at ${LAUNCH_DAEMON_SETTINGS_PATH}."
}

################################################################################
#  Downloads the Installer
#  Globals:
#    None
#  Arguments:
#    my_jamf_trigger
#  Locals:
#    my_jamf_trigger
#    my_jamfHelper_pid
#  Returns:
#    None
#  Error code range: 280-299
################################################################################
function download_installer()
{
  local my_jamf_trigger="$1"

  /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
    -windowType hud \
    -windowPosition ul \
    -title "Downloading ${MACOS_NAME} Installer" \
    -description "The process of downloading ${MACOS_NAME} may take up to 30 minutes.  Please do not restart or power off your computer." \
    -lockHUD \
    -icon "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/SidebarDownloadsFolder.icns" \
    -iconSize 100 &
    
  my_jamfHelper_pid=$!

  if /usr/local/jamf/bin/jamf policy -event "${my_jamf_trigger}"; then
    /bin/sleep 5
    kill_process "${my_jamfHelper_pid}"
  else
    /bin/sleep 5
    kill_process "${my_jamfHelper_pid}"

    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
      -windowType utility \
      -title "System Requirements Error (Installer Download)" \
      -description "There was a problem verifying your system requirements.  Please contact your ITS representative to resolve this issue.  Unable to download macOS installer application." \
      -button1 "OK" \
      -defaultButton 1 \
      -timeout 600 \
      -icon "${ERROR_ICON_PATH}" \
      -iconSize 250 &

    message 280 "Cannot download installer for ${MACOS_NAME}."
  fi
}

################################################################################
#  Main function
#  System:
#    None
#  Globals:
#    MACOS_NAME
#    OS_INSTALL_LOG
#    OS_VERSION_BASE
#    ERROR_ICON_PATH
#    WARNING_ICON_PATH
#    WARNING_ICON_PATH_BIG_SUR
#    WARNING_ICON_PATH_PRE_BIG_SUR
#    COMPUTER_NAME
#    LAUNCH_AGENT_SETTINGS_PATH
#    LOGGED_IN_USERNAME
#    MOUNT_POINT
#  Arguments:
#    arg_array
#  Locals:
#    arg_array()
#    startos_install_options()
#    do_fv_auth_reboot
#    download_trigger
#    erase_and_install
#    installer_checksum
#    installer_path
#    installer_version
#    installer_version_base
#    installer_version_major
#    jamfHelper_pid
#    logged_in_user_id
#    minimum_ram
#    minimum_storage
#    startos_install_command
#    status_checksum
#    status_fv
#    status_fv_complete
#    status_power
#    status_ram
#    status_storage
#  Returns:
#    None
#  Error code range: 1-99
################################################################################
function main()
{
  # For jss scripts, the following is true:
  # Variable $1 is defined as mount point
  # Variable $2 is defined as computer name
  # Variable $3 is defined as username (That is the currently logged
  #   in user or root if at the loginwindow.

  local arg_array=()
  local startos_install_options=()
  local do_fv_auth_reboot=0
  local download_trigger=""
  local erase_and_install=""
  local installer_checksum=""
  local installer_path=""
  local installer_version=""
  local installer_version_base=""
  local installer_version_major=""
  local jamfHelper_pid=""
  local logged_in_user_id=""
  local minimum_ram=""
  local minimum_storage=""
  local startos_install_command=""
  local status_checksum=""
  local status_fv=""
  local status_fv_complete=""
  local status_power=""
  local status_ram=""
  local status_storage=""

################################################################################
#
#  Process arguments passed in to script
#
################################################################################

  # Verify arguments are passed in.  Otherwise exit.
  if [[ "$#" -eq 0 ]]; then
    message 1 "No parameters passed to script."
  else
    arg_array=( "$@" )
  fi

  # Get the variables passed in and clean up if necessary.
  if [[ -z "${MOUNT_POINT}" ]]; then
    MOUNT_POINT="${arg_array[0]}"
  fi
  if [[ "${DEBUG}" == "TRUE" ]]; then
    message 0 "Mount Point BEFORE stripping a trailing slash (/) " \
      "is \"${MOUNT_POINT}\"."
  fi
  unset 'arg_array[0]'	# Remove MOUNT_POINT from the arg_array
  MOUNT_POINT="${MOUNT_POINT%/}"	# This removes a trailing '/' if present.
  if [[ "${DEBUG}" == "TRUE" ]]; then
    message 0 "Mount Point AFTER stripping a trailing slash (/) " \
      "is \"${MOUNT_POINT}\"."
  fi

  if [[ -z "${COMPUTER_NAME}" ]]; then
    COMPUTER_NAME="${arg_array[1]}"
  fi
  if [[ "${DEBUG}" == "TRUE" ]]; then
    message 0 "Computer name is \"${COMPUTER_NAME}\"."
  fi
  unset 'arg_array[1]'	# Remove COMPUTER_NAME from the arg_array

  if [[ -z "${LOGGED_IN_USERNAME}" ]]; then
    LOGGED_IN_USERNAME="${arg_array[2]}"
  fi

  if [[ -z "${LOGGED_IN_USERNAME}" ]]; then
    if [[ "${DEBUG}" == "TRUE" ]]; then
      message 0 "No user currently logged in."
    fi
  else
    if [[ "${DEBUG}" == "TRUE" ]]; then
      message 0 "Logged in Username is \"${LOGGED_IN_USERNAME}\"."
    fi
  fi
  unset 'arg_array[2]'	# Remove LOGGED_IN_USERNAME from the arg_array

  # Specify full path to installer.  Use parameter 4 in the Jamf Pro Server
  # Ex: "/Applications/Install macOS Catalina.app"
  # Ex: "/Applications/Install macOS Big Sur.app"
  installer_path="${arg_array[3]}"
  if [[ -z "${installer_path}" ]]; then
    message 2 "The macOS installer path was not specified.  Example: \"/Applications/Install macOS Big Sur.app\""
  fi
  if [[ "${DEBUG}" == "TRUE" ]]; then
    message 0 "The macOS installer path has been set to \"${installer_path}\"."
  fi
  unset 'arg_array[3]'

  # Go ahead and get the macOS name from the installer path.
  MACOS_NAME="$(/bin/echo "${installer_path}" | /usr/bin/sed 's/^\/Applications\/Install \(.*\)\.app$/\1/')"
  if [[ "${DEBUG}" == "TRUE" ]]; then
    message 0 "macOS name set to \"${MACOS_NAME}\"."
  fi

  # Installer version.  Use parameter 5 in the Jamf Pro Server.
  # Command to get the installer version: `/usr/libexec/PlistBuddy -c 'Print :"System Image Info":version' "/Applications/Install macOS Big Sur.app/Contents/SharedSupport/InstallInfo.plist"
  # Ex: 11.2.3
  installer_version="${arg_array[4]}"
  if [[ -z "${installer_version}" ]]; then
    message 3 "The macOS installer version was not specified.  Please get the installer version from either the SharedSupport/InstallInfo.plist or the App Contents/Info.plist."
  elif [[ ! "${installer_version}" =~ ^[0-9]{2}\.?[0-9]{1,2}\.?[0-9]?$ ]]; then
    message 4 "Unknown macOS version format.  Version should be in the form of OS_Base.OS_Major.OS_Minor.  Ex: 11.2.3 or 10.15.7"
  fi
  if [[ "${DEBUG}" == "TRUE" ]]; then
    message 0 "macOS installer version set to \"${installer_version}\"."
  fi
  unset 'arg_array[4]'

  installer_version_base="$(/bin/echo "${installer_version}" | /usr/bin/awk -F. '{print $1}')"
  installer_version_major="$(/bin/echo "${installer_version}" | /usr/bin/awk -F. '{print $2}')"
#  installer_version_minor="$(/bin/echo "${installer_version}" | /usr/bin/awk -F. '{print $3}')"

  # Download trigger.  This is the custom trigger on a Jamf Pro policy used to
  # manage the macOS installer download. This policy should only have a single
  # package (the macOS installer) and should not have any other scripts or
  # configuration. The policy should be set to ongoing with no other triggers
  # and should not have Self Service enabled. The only way this policy should
  # execute is by being called using this custom trigger.
  # Set the scope accordingly.
  download_trigger="${arg_array[5]}"
  if [[ -z "${download_trigger}" ]]; then
    message 5 "No download trigger specified.  Cannot download macOS installer."
  fi
  if [[ "${DEBUG}" == "TRUE" ]]; then
    message 0 "The download trigger is set to \"${download_trigger}\"."
  fi
  unset 'arg_array[5]'

  # (OPTIONAL) md5 checksum of InstallESD.dmg
  # This optional value serves to validate the macOS installer.
  # Command to get the md5 checksum: `/sbin/md5 "/Applications/Install macOS Big Sur.app/Contents/SharedSupport/SharedSupport.dmg"
  # (InstallESD.dmg for pre-Big Sur)"
  # Ex: b15b9db3a90f9ae8a9df0f812741e52ad
  installer_checksum="${arg_array[6]}"
  if [[ -z "${installer_checksum}" ]]; then
    message -1 "No MD5 checksum supplied.  Installer will be assumed valid."
  fi
  if [[ "${DEBUG}" == "TRUE" ]]; then
    message 0 "MD5 Checksum set to \"${installer_checksum}\"."
  fi
  unset 'arg_array[6]'

  # Erase and Install Option. This instructs the installer to erase the local
  # hard drive before continuing with the macOS install.  This option is only
  # valid for macOS installer version 10.13.4 or later and macOS client
  # version 10.13 or later.
  erase_and_install="${arg_array[7]}"
  if [[ -z "${erase_and_install}" ]]; then
    message 0 "Factory Reset was NOT selected.  Proceeding with Upgrade."
  elif [[ "${erase_and_install}" =~ ^[01]$ ]]; then
    if ((erase_and_install == 0 )); then
      message 0 "Factory Reset was NOT selected.  Proceeding with Upgrade."
    else
      message 0 "Factory Reset HAS been selected.  Storage on this computer will be wiped before installation proceeds."
      startos_install_options+=("--eraseinstall")
    fi
  else
    message 6 "Unknown input.  Erase and install is set to \"${erase_and_install}\"."
  fi
  unset 'arg_array[7]'

  startos_install_options+=(
    "--agreetolicense"
    "--nointeraction"
  )

################################################################################
#
#  Based on Installer Version or Host Version, set appropriate minimum
#  requirements and other settings.
#
################################################################################
  case "${OS_VERSION_BASE}" in
    11)
      WARNING_ICON_PATH="${WARNING_ICON_PATH_BIG_SUR}"
      ;;
    10)
      WARNING_ICON_PATH="${WARNING_ICON_PATH_PRE_BIG_SUR}"
      ;;
  esac

  case "${installer_version_base}" in
    11)
      minimum_ram="${REQUIRED_MINIMUM_RAM_110}"
      minimum_storage="${REQUIRED_MINIMUM_STORAGE_110}"
      do_fv_auth_reboot=0
      startos_install_options+=("--forcequitapps")
      ;;
    10)
      case "${installer_version_major}" in
        15)
          minimum_ram="${REQUIRED_MINIMUM_RAM_1015}"
          minimum_storage="${REQUIRED_MINIMUM_STORAGE_1015}"
          do_fv_auth_reboot=0
          startos_install_options+=("--forcequitapps")
          ;;
        14)
          minimum_ram="${REQUIRED_MINIMUM_RAM_1014}"
          minimum_storage="${REQUIRED_MINIMUM_STORAGE_1014}"
          do_fv_auth_reboot=0
          ;;
        13)
          minimum_ram="${REQUIRED_MINIMUM_RAM_1013}"
          minimum_storage="${REQUIRED_MINIMUM_STORAGE_1013}"
          do_fv_auth_reboot=1
          startos_install_options+=("--applicationpath \"${installer_path}\"")
          ;;
        *)
          message 8 "Unknown Installer OS: ${installer_version}."
          ;;
      esac
      ;;
    *)
      message 7 "Unknown Installer OS: ${installer_version}."
      ;;
  esac

################################################################################
#
#  Perform system checks
#
################################################################################
  check_free_storage "${minimum_storage}" "${installer_path}" status_storage
  check_ram "${minimum_ram}" status_ram
  check_power status_power
  check_filevault status_fv status_fv_complete

  if [[ -d "${installer_path}" ]] && [[ -n "${installer_checksum}" ]]; then
    check_checksum "${installer_path}" "${installer_checksum}" status_checksum
    if [[ "${status_checksum}" != "OK" ]]; then
      download_installer "${download_trigger}"
    fi
  else
    download_installer "${download_trigger}"
  fi

  if [[ -n "${installer_checksum}" ]] && [[ "${status_checksum}" != "OK" ]]; then
    check_checksum "${installer_path}" "${installer_checksum}" status_checksum
    if [[ "${status_checksum}" != "OK" ]]; then
      message 9 "Cannot verify downloaded installer with given checksum."
    fi
  fi

  create_first_boot_script "${installer_path}"
  create_launch_daemon_plist

  if [[ "${do_fv_auth_reboot}" ]]; then
    create_launch_agent_filevault_reboot_plist "${installer_path}"
  fi

  # Check power status one more time before actually beginning the installation.
  check_power status_power

  if [[ "${status_power}" != "OK" ]] || [[ "${status_storage}" != "OK" ]] || [[ "${status_ram}" != "OK" ]] || [[ "${status_fv}" != "OK" ]] || [[ "${status_checksum}" != "OK" ]]; then
    if [[ "${DEBUG}" == "TRUE" ]]; then
      message 0 "Power status: ${status_power}."
      message 0 "Storage status: ${status_storage}."
      message 0 "RAM status: ${status_ram}."
      message 0 "FileVault status: ${status_fv} - ${status_fv_complete}."
      message 0 "Checksum status: ${status_checksum}."
    fi

    /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
      -windowType utility \
      -title "System Requirements Error" \
      -description "There was a problem verifying your system requirements.  Please contact your ITS representative to resolve this issue." \
      -button1 "OK" \
      -defaultButton 1 \
      -timeout 600 \
      -icon "${ERROR_ICON_PATH}" \
      -iconSize 250 &
    
    clean_up_install_files
    message 10 "Exit with Jamf Helper."
  fi




#  if [[ $fvStatus == "FileVault is On." && $loggedInUsername != "root" ]]; then
#    if (( installerVersionMajor < 14 )); then
#      message 0 "Loading com.apple.install.osinstallersetupd.plist with launchctl into ${loggedInUsername}'s gui context."
#      /bin/launchctl bootstrap gui/"$loggedInUsername" /Library/LaunchAgents/com.apple.install.osinstallersetupd.plist
#    fi
#  fi

  /Library/Application\ Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper \
    -windowType fs \
    -title "" \
    -heading "Please wait as ${MACOS_NAME} is installed." \
    -description "Installation of ${MACOS_NAME} has started.  Please allow up to an hour for installation to complete.  Contact your ITS representative if you have any questions or concerns during this process." \
    -icon "${installer_path}/Contents/Resources/InstallAssistant.icns" &

  jamfHelper_pid=$!
  startos_install_options+=("--pidtosignal ${jamfHelper_pid}")

  if [[ "${status_fv_complete}" == "FileVault is On." ]] && [[ "${LOGGED_IN_USERNAME}" != "root" ]] && ((do_fv_auth_reboot == 1)); then
    logged_in_user_id="$(/usr/bin/id -u "${LOGGED_IN_USERNAME}")"
    message 0 "Using LaunchAgent as user (${logged_in_user_id}) ${LOGGED_IN_USERNAME}."
    /bin/launchctl bootstrap gui/"${logged_in_user_id}" "${LAUNCH_AGENT_SETTINGS_PATH}"
  fi
  startos_install_command="\"${installer_path}/Contents/Resources/startosinstall\" ${startos_install_options[*]} >> ${OS_INSTALL_LOG} 2>&1 &"
  message 0 "Running ${startos_install_command}"

  if [[ "${DEBUG}" == "FALSE" ]]; then
    message 0 "Begin startos_install_command"
    eval "${startos_install_command}"
    /bin/sleep 3
    /bin/launchctl asuser "${logged_in_user_id}" /usr/bin/open "${OS_INSTALL_LOG}"
  else
    message 0 "Options for startos_install are: ${startos_install_options[*]}."
    count=0
    while ((count <= 10)); do
      message 0 "Count (${count})"
      /bin/sleep 1
      ((count++))
    done
    kill_process "${jamfHelper_pid}"
    clean_up_install_files
  fi
}

################################################################################
#
#  Special section to make sure nothing is still running from a previous
#  macOS install attempt.
#
################################################################################

message 0 "Killing any remaining installers from a previous install."
for TEMP_PROCESS in "${PREVIOUS_PROCESSES[@]}"; do
  if [[ "${DEBUG}" == "TRUE" ]]; then
    message 0 "Stopping process ${TEMP_PROCESS} from a previous install."
    /usr/bin/killall "${TEMP_PROCESS}" 2>&1 || true
  fi
done
################################################################################

# Caffeinate
/usr/bin/caffeinate -dis &
CAFFEINATE_PID=$!

if [[ ! -d "${LOG_DIR}" ]]; then
  /bin/mkdir -p "${LOG_DIR}"
fi

if [[ -e "${LOG}" ]]; then
  /bin/rm "${LOG}"
fi

if [[ -e "${OS_INSTALL_LOG}" ]]; then
  /bin/rm -f "${OS_INSTALL_LOG}"
fi
  
/usr/bin/touch "${LOG_DATE}"
/usr/bin/touch "${OS_INSTALL_LOG}"
/bin/ln -s "${LOG_DATE}" "${LOG}"
message 0 "BEGIN: ${LOG} ${DATE}"
if [[ "${DEBUG}" == "TRUE" ]]; then
  message 0 "MODE: DEBUG"
fi

if [[ "${DEBUG}" == "TRUE" ]]; then
  message 0 "Disabling sleep during script.  Caffeinate PID is ${CAFFEINATE_PID}."
fi
main "$@"
finish