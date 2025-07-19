#!/usr/bin/env bash
set -euo pipefail # Crucial for robust error handling

SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
CONFIGS_DIR="$SCRIPTPATH/configs"
CONFIG_FILE="$CONFIGS_DIR/setup.conf"
LOG_FILE="$SCRIPTPATH/startup.log"


exec &> >(tee -a "$LOG_FILE")

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error_exit() {
    log_message "FATAL ERROR: $1" >&2
    echo "🚨 ERROR: $1" >&2
    echo "Please check the log file: $LOG_FILE for more details." >&2
    exit 1
}

check_command() {
    local cmd_description="${1}" # The first argument is the description
    shift # Remove the description, rest are actual command
    log_message "Executing: $* ($cmd_description)"
    if ! "$@"; then
        error_exit "Command '$*' ($cmd_description) failed with status $?."
    fi
}

set_option() {
    local key="$1"
    local value="$2"
    if grep -Eq "^${key}.*" "$CONFIG_FILE"; then # check if option exists
        check_command "Deleting existing option for $key" sed -i -e "/^${key}.*/d" "$CONFIG_FILE"
    fi
    log_message "Setting option: ${key}=${value}"
    check_command "Adding option: ${key}=${value}" echo "${key}=${value}" >> "$CONFIG_FILE" 
}


set_password() {
    local var_name="$1"
    local retries=3
    while [[ $retries -gt 0 ]]; do
        echo -ne "\n🔑 Please enter password for ${var_name}: "
        read -rs PASSWORD_INPUT_1
        echo -ne "\n"
        echo -ne "🔑 Please re-enter password for ${var_name}: "
        read -rs PASSWORD_INPUT_2
        echo -ne "\n"

        if [[ "$PASSWORD_INPUT_1" == "$PASSWORD_INPUT_2" ]]; then
            set_option "$var_name" "$PASSWORD_INPUT_1"
            log_message "Password for '$var_name' successfully set."
            unset PASSWORD_INPUT_1 PASSWORD_INPUT_2 # Clear sensitive data
            return 0
        else
            log_message "ERROR: Passwords do not match. Retries left: $((--retries))."
            echo -ne "🔥 ERROR! Passwords do not match. Please try again. ($retries retries left)\n"
        fi
    done
    error_exit "Failed to set password for '$var_name' after multiple attempts."
}

root_check() {
    if [[ "$(id -u)" != "0" ]]; then
        error_exit "This script must be run under the 'root' user!"
    fi
    log_message "Root user check passed."
}

docker_check() {
    if awk -F/ '$2 == "docker"' /proc/self/cgroup | read -r || [[ -f /.dockerenv ]]; then
        error_exit "Docker container environment is not supported for this installation (at the moment)."
    fi
    log_message "Docker container check passed."
}

arch_check() {
    if [[ ! -e /etc/arch-release ]]; then
        error_exit "This script must be run in Arch Linux!"
    fi
    log_message "Arch Linux check passed."
}

pacman_check() {
    if [[ -f /var/lib/pacman/db.lck ]]; then
        error_exit "Pacman database is locked (/var/lib/pacman/db.lck). Please ensure no other pacman process is running."
    fi
    log_message "Pacman lock check passed."
}

background_checks() {
    log_message "Performing initial background checks..."
    root_check
    arch_check
    pacman_check
    docker_check
    log_message "All background checks passed."
}


select_option() {
    local colmax=$1
    shift # Remove colmax from arguments
    local options=("$@") # Remaining arguments are options

    ESC=$( printf "\033")
    cursor_blink_on()  { printf "$ESC[?25h"; }
    cursor_blink_off() { printf "$ESC[?25l"; }
    cursor_to()        { printf "$ESC[$1;${2:-1}H"; }
    print_option()     { printf "$2   $1 "; } # Adjusted spacing for consistency
    print_selected()   { printf "$2 $ESC[7m $1 $ESC[27m"; } # Adjusted spacing
    get_cursor_row()   { IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${ROW#*[}; }
    get_cursor_col()   { IFS=';' read -sdR -p $'\E[6n' ROW COL; echo ${COL#*[}; }
    key_input()        {
        local key
        IFS= read -rsn1 key 2>/dev/null >&2
        if [[ $key = ""      ]]; then echo enter; fi;
        if [[ $key = $'\x20' ]]; then echo space; fi;
        if [[ $key = "k" ]]; then echo up; fi;
        if [[ $key = "j" ]]; then echo down; fi;
        if [[ $key = "h" ]]; then echo left; fi;
        if [[ $key = "l" ]]; then echo right; fi;
        if [[ $key = "a" ]]; then echo all; fi;
        if [[ $key = "n" ]]; then echo none; fi;
        if [[ $key = $'\x1b' ]]; then
            read -rsn2 key
            if [[ $key = [A || $key = k ]]; then echo up;    fi;
            if [[ $key = [B || $key = j ]]; then echo down;  fi;
            if [[ $key = [C || $key = l ]]; then echo right;  fi;
            if [[ $key = [D || $key = h ]]; then echo left;  fi;
        fi
    }
    print_options_multicol() {
        local curr_col=$1
        local curr_row=$2
        local curr_idx=0

        local idx=0
        local row=0
        local col=0
        
        curr_idx=$(( curr_col + curr_row * colmax ))
        
        for option in "${options[@]}"; do
            row=$(( idx / colmax ))
            col=$(( idx - row * colmax ))

            cursor_to $(( startrow + row + 1)) $(( offset * col + 1))
            if [ $idx -eq $curr_idx ]; then
                print_selected "$option" "➡️" 
            else
                print_option "$option" "  " 
            fi
            ((idx++))
        done
    }

    for opt in "${options[@]}"; do printf "\n"; done

    local lastrow=$(get_cursor_row)
    local lastcol=$(get_cursor_col)
    local startrow=$((lastrow - ${#options[@]})) # Corrected to count of options
    local startcol=1
    local lines=$( tput lines )
    local cols=$( tput cols ) 
    
    local offset=$(( cols / colmax ))

    trap "cursor_blink_on; stty echo; printf '\n'; exit" 2
    cursor_blink_off

    local active_row=0
    local active_col=0
    while true; do
        print_options_multicol $active_col $active_row 
        case $(key_input) in
            enter)  break;;
            up)     ((active_row--));
                    if [ $active_row -lt 0 ]; then active_row=0; fi;;
            down)   ((active_row++));
                    if [ $(( active_row * colmax )) -ge ${#options[@]} ]; then active_row=$(( (${#options[@]} - 1) / colmax )) ; fi;; # Corrected bounds check
            left)   ((active_col=active_col - 1));
                    if [ $active_col -lt 0 ]; then active_col=0; fi;;
            right)  ((active_col=active_col + 1));
                    if [ $active_col -ge $colmax ]; then active_col=$(( colmax - 1 )) ; fi;;
        esac
    done

    cursor_to $lastrow
    printf "\n"
    cursor_blink_on

    return $(( active_col + active_row * colmax ))
}

logo () {
echo -ne "
-------------------------------------------------------------------------
                                                                                                                                                          
                               ,,                                  ,,                                                     ,,                              
      db                     `7MM        `7MM"""YMM              `7MM                                                   `7MM  `7MMF'`7MN.   `7MF'.M"""bgd 
     ;MM:                      MM          MM    `7                MM                                                     MM    MM    MMN.    M ,MI    "Y 
    ,V^MM.    `7Mb,od8 ,p6"bo  MMpMMMb.    MM   d    `7MMpMMMb.    MMpMMMb.   ,6"Yb.  `7MMpMMMb.  ,p6"bo   .gP"Ya    ,M""bMM    MM    M YMb   M `MMb.     
   ,M  `MM      MM' "'6M'  OO  MM    MM    MMmmMM      MM    MM    MM    MM  8)   MM    MM    MM 6M'  OO  ,M'   Yb ,AP    MM    MM    M  `MN. M   `YMMNq. 
   AbmmmqMA     MM    8M       MM    MM    MM   Y  ,   MM    MM    MM    MM   ,pm9MM    MM    MM 8M       8M"""""" 8MI    MM    MM    M   `MM.M .     `MM 
  A'     VML    MM    YM.    , MM    MM    MM     ,M   MM    MM    MM    MM  8M   MM    MM    MM YM.    , YM.    , `Mb    MM    MM    M     YMM Mb     dM 
.AMA.   .AMMA..JMML.   YMbmd'.JMML  JMML..JMMmmmmMMM .JMML  JMML..JMML  JMML.`Moo9^Yo..JMML  JMML.YMbmd'   `Mbmmd'  `Wbmd"MML..JMML..JML.    YM P"Ybmmd"  
                                                                                                                                                          
                                                                                                                                                          
------------------------------------------------------------------------
       Please select presetup settings for your system           
------------------------------------------------------------------------
"
log_message "Displayed installer logo and welcome message."
}

filesystem () {
    log_message "Starting filesystem selection."
    echo -ne "
Please Select your file system for both boot and root
"
    local options=("btrfs" "ext4" "luks" "exit")
    select_option 1 "${options[@]}"
    local choice_idx=$?

    case ${options[$choice_idx]} in
    "btrfs") set_option FS btrfs; log_message "Filesystem selected: btrfs.";;
    "ext4") set_option FS ext4; log_message "Filesystem selected: ext4.";;
    "luks") 
        set_password "LUKS_PASSWORD"
        set_option FS luks
        log_message "Filesystem selected: luks. LUKS password set."
        ;;
    "exit") log_message "User chose to exit during filesystem selection."; exit 0 ;;
    *) log_message "Invalid option selected for filesystem. Trying again."; filesystem;; # Recursive call
    esac
}

# @description Detects and sets timezone. 
timezone () {
    log_message "Starting timezone configuration."
    local time_zone=""
    log_message "Attempting to detect timezone via ipapi.co..."
    if ! time_zone=$(curl --fail --silent --show-error https://ipapi.co/timezone); then
        log_message "WARNING: Could not auto-detect timezone via curl. Error: $time_zone. Prompting user manually."
        echo -ne "Failed to auto-detect timezone. Please enter your desired timezone (e.g., 'America/Los_Angeles'): "
        read -r new_timezone
    else
        echo -ne "
System detected your timezone to be '${time_zone}' \n"
        echo -ne "Is this correct?
" 
        local options=("Yes" "No")
        select_option 1 "${options[@]}"
        local choice_idx=$?

        case ${options[$choice_idx]} in
            "Yes")
                log_message "${time_zone} set as timezone (auto-detected)."
                set_option TIMEZONE "$time_zone";;
            "No")
                echo -ne "Please enter your desired timezone (e.g., 'Europe/London'): "
                read -r new_timezone
                ;;
            *)
                log_message "Invalid option for timezone confirmation. Prompting for manual entry."
                echo -ne "Invalid option. Please enter your desired timezone (e.g., 'Europe/London'): "
                read -r new_timezone
                ;;
        esac
    fi

    if [[ -n "$new_timezone" ]]; then 
        if ! timedatectl list-timezones | grep -q "^${new_timezone}$"; then
            log_message "Invalid timezone entered: '${new_timezone}'. Please enter a valid one."
            echo -ne "? Invalid timezone '${new_timezone}'. Please enter a valid timezone from 'timedatectl list-timezones': \n"
            timezone # Recursive call for re-entry
            return # Exit current function instance
        fi
        log_message "${new_timezone} set as timezone (manual entry)."
        set_option TIMEZONE "$new_timezone"
    fi
}

keymap () {
    log_message "Starting keyboard layout (keymap) selection."
    echo -ne "
Please select keyboard layout from this list"
    local options=(us by ca cf cz de dk es et fa fi fr gr hu il it lt lv mk nl no pl ro ru sg ua uk)

    select_option 4 "${options[@]}"
    local choice_idx=$?
    local keymap=${options[$choice_idx]}

    echo -ne "Your keyboard layout: ${keymap} \n"
    set_option KEYMAP "$keymap"
    log_message "Keyboard layout set to: ${keymap}."
}

drivessd () {
    log_message "Starting SSD detection for mount options."
    echo -ne "
Is this an SSD? (Yes/No):
"

    local options=("Yes" "No")
    select_option 1 "${options[@]}"
    local choice_idx=$?

    case ${options[$choice_idx]} in
        "Yes")
            set_option MOUNT_OPTIONS "noatime,compress=zstd,ssd,commit=120"
            log_message "Drive detected as SSD. Mount options set: noatime,compress=zstd,ssd,commit=120.";;
        "No")
            set_option MOUNT_OPTIONS "noatime,compress=zstd,commit=120"
            log_message "Drive detected as HDD. Mount options set: noatime,compress=zstd,commit=120.";;
        *) log_message "Invalid option for SSD detection. Trying again."; drivessd;; 
    esac
}

diskpart () {
    log_message "Starting disk selection."
    echo -ne "
------------------------------------------------------------------------
    ⚠ THIS WILL FORMAT AND DELETE ALL DATA ON THE DISK ⚠
    Please make sure you know what you are doing because
    after formatting your disk there is no way to get data back
------------------------------------------------------------------------

"

    echo -ne "Select the disk to install on: "
    local options=($(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print "/dev/"$2"|"$3}'))

    if [[ ${#options[@]} -eq 0 ]]; then
        error_exit "No disks found. Please ensure disks are visible to the system."
    fi

    select_option 1 "${options[@]}"
    local choice_idx=$?
    local disk_info=${options[$choice_idx]}
    local disk_path=${disk_info%|*}

    echo -e "\nSelected disk: ${disk_path} \n"
    set_option DISK "$disk_path"
    log_message "Selected disk: $disk_path."

    # Validate that the selected disk is indeed a block device
    if [[ ! -b "$disk_path" ]]; then
        error_exit "Selected item '$disk_path' is not a valid block device. Please re-run the script and select a proper disk."
    fi

    drivessd # Call drivessd after disk is selected
}

userinfo () {
    log_message "Starting user and hostname information gathering."
    local username_input
    local hostname_input

    # Username
    while true; do
        read -rp "Please enter your username (lowercase, no spaces, starts with letter/underscore): " username_input
        if [[ -z "$username_input" ]]; then
            echo -ne "Username cannot be empty. Please try again.\n"
            log_message "Username input empty."
        elif [[ ! "$username_input" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
            echo -ne "? Invalid username format. Must start with a letter/underscore, contain only letters, numbers, hyphens, underscores. Please try again.\n"
            log_message "Invalid username format: '$username_input'."
        else
            break
        fi
    done
    set_option USERNAME "${username_input,,}" # Convert to lower case
    log_message "Username set to: ${username_input,,}."

    set_password "PASSWORD" 

    while true; do
        read -rp "Please enter your hostname: " hostname_input
        if [[ -z "$hostname_input" ]]; then
            echo -ne "Hostname cannot be empty. Please try again.\n"
            log_message "Hostname input empty."
        elif [[ ! "$hostname_input" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]$ ]]; then 
            echo -ne "? Invalid hostname. Must start/end with alphanumeric, contain only letters, numbers, dots, or hyphens. Please try again.\n"
            log_message "Invalid hostname format: '$hostname_input'."
        else
            break
        fi
    done
    set_option NAME_OF_MACHINE "$hostname_input"
    log_message "Hostname set to: $hostname_input."
}

aurhelper () {
    log_message "Starting AUR helper selection."
    echo -ne "Please select your desired AUR helper:\n"
    local options=(paru yay picaur aura trizen pacaur none)
    select_option 4 "${options[@]}"
    local choice_idx=$?
    local aur_helper=${options[$choice_idx]}
    set_option AUR_HELPER "$aur_helper"
    log_message "AUR helper selected: $aur_helper."
}

desktopenv () {
    log_message "Starting Desktop Environment selection."
    echo -ne "Please select your desired Desktop Environment:\n"
    local options=( $(for f in "$PKG_FILES_DIR"/*.txt; do basename "$f" .txt; done | grep -v 'pkgs' | sort) )
    
    if [[ ${#options[@]} -eq 0 ]]; then
        error_exit "No desktop environment package lists found in '$PKG_FILES_DIR'. Please check your installer directory."
    fi

    select_option 4 "${options[@]}"
    local choice_idx=$?
    local desktop_env_chosen=${options[$choice_idx]} # Use a local var for choice
    set_option DESKTOP_ENV "$desktop_env_chosen"
    log_message "Desktop environment selected: $desktop_env_chosen."

    desktop_env="$desktop_env_chosen"
}

installtype () {
    log_message "Starting installation type selection."
    echo -ne "Please select type of installation:\n\n
    Full install: Installs full featured desktop environment, with added apps and themes needed for everyday use\n
    Minimal Install: Installs only a few selected apps to get you started\n"
    local options=(FULL MINIMAL)
    select_option 4 "${options[@]}"
    local choice_idx=$?
    local install_type=${options[$choice_idx]}
    set_option INSTALL_TYPE "$install_type"
    log_message "Installation type selected: $install_type."
}

log_message "--- Starting ArchEnhancedINS Setup Wizard ---"

if [ ! -d "$CONFIGS_DIR" ]; then
    check_command "Creating configs directory" mkdir -p "$CONFIGS_DIR"
fi

if [ ! -f "$CONFIG_FILE" ]; then
    log_message "Creating new setup.conf at $CONFIG_FILE"
    check_command "Creating setup.conf" touch "$CONFIG_FILE"
else
    log_message "Using existing setup.conf at $CONFIG_FILE"
fi

PKG_FILES_DIR="$SCRIPTPATH/pkg-files"
if [ ! -d "$PKG_FILES_DIR" ]; then
    error_exit "Package files directory '$PKG_FILES_DIR' not found!"
fi


background_checks # Perform initial system checks
clear # Clear screen after checks

logo # Display the main logo

userinfo # Gather username, user password, and hostname
clear
logo

desktopenv # Choose Desktop Environment (sets desktop_env variable)
log_message "Selected Desktop Environment: $desktop_env"

if [[ "$desktop_env" == "server" ]]; then
    log_message "Server installation detected. Setting INSTALL_TYPE to MINIMAL and AUR_HELPER to NONE."
    set_option INSTALL_TYPE MINIMAL
    set_option AUR_HELPER NONE
else
    clear
    logo
    aurhelper # Choose AUR helper
    clear
    logo
    installtype # Choose installation type (FULL/MINIMAL)
fi

clear
logo
diskpart # Choose disk and determine SSD/HDD for mount options
clear
logo
filesystem # Choose filesystem (ext4, btrfs, luks) and handle LUKS password
clear
logo
timezone # Set timezone
clear
logo
keymap # Set keyboard layout

log_message "All startup configurations collected and saved to $CONFIG_FILE."
echo -ne "
-------------------------------------------------------------------------
                     Configuration complete. Ready for next step.
-------------------------------------------------------------------------
"
exit 0
