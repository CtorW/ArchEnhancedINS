#!/bin/bash
# Enable strict mode: exit on error, unset variables, and pipefail
set -euo pipefail

set -a

SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
CONFIGS_DIR="$SCRIPT_DIR/configs"

# set +a

run_stage() {
    local script_path="$1"
    local log_file="$2"
    local description="$3"
    local chroot_cmd="$4" # "arch-chroot" or ""

    echo -ne "\n--- Starting $description ---\n"


    local temp_log=$(mktemp)

    if [[ -n "$chroot_cmd" ]]; then
      
        if ! ($chroot_cmd "$script_path") 2>&1 | tee "$temp_log"; then
            echo "ERROR: $description failed!" | tee -a "$log_file"
            cat "$temp_log" >> "$log_file" # Append temp log to final log
            rm "$temp_log"
            exit 1
        fi
    else
        
        if ! (bash "$script_path") 2>&1 | tee "$temp_log"; then
            echo "ERROR: $description failed!" | tee -a "$log_file"
            cat "$temp_log" >> "$log_file" # Append temp log to final log
            rm "$temp_log"
            exit 1
        fi
    fi

    cat "$temp_log" >> "$log_file" # Append the output to the main log file
    rm "$temp_log"
    echo -ne "--- $description Completed Successfully ---\n"
}

echo -ne "
-------------------------------------------------------------------------                                                     
 ▄▀█ █▀█ █▀▀ █░█ █▀▀ █▄░█ █░█ ▄▀█ █▄░█ █▀▀ █▀▀ █▀▄ █ █▄░█ █▀
 █▀█ █▀▄ █▄▄ █▀█ ██▄ █░▀█ █▀█ █▀█ █░▀█ █▄▄ ██▄ █▄▀ █ █░▀█ ▄█
-------------------------------------------------------------------------
                    Automated Arch Linux Installer
-------------------------------------------------------------------------
                Scripts are in directory named ArchEnhancedINS
"


run_stage "$SCRIPTS_DIR/startup.sh" "startup.log" "Initial Setup (startup.sh)" ""

if [[ ! -f "$CONFIGS_DIR/setup.conf" ]]; then
    echo "ERROR: Configuration file '$CONFIGS_DIR/setup.conf' not found! Exiting." >&2
    exit 1
fi
source "$CONFIGS_DIR/setup.conf" # Variables like DESKTOP_ENV, USERNAME should be here

run_stage "$SCRIPTS_DIR/0-preinstall.sh" "0-preinstall.log" "Pre-Installation (0-preinstall.sh)" ""

run_stage "/mnt$HOME/ArchEnhancedINS/scripts/1-setup.sh" "1-setup.log" "Chrooted Setup (1-setup.sh)" "arch-chroot /mnt"

if [[ ! "$DESKTOP_ENV" == server ]]; then
   
    if [[ -z "$USERNAME" ]]; then
        echo "ERROR: USERNAME variable not set in setup.conf! Cannot run user script." >&2
        exit 1
    fi
   
    run_stage "/mnt/usr/bin/runuser -u $USERNAME -- /home/$USERNAME/ArchEnhancedINS/scripts/2-user.sh" "2-user.log" "User Specific Setup (2-user.sh)" "arch-chroot /mnt"
fi

run_stage "/mnt$HOME/ArchEnhancedINS/scripts/3-post-setup.sh" "3-post-setup.log" "Post-Setup (3-post-setup.sh)" "arch-chroot /mnt"

echo -ne "\n--- Copying logs to new system ---\n"
if [[ -d "/mnt/home/$USERNAME" ]]; then
    cp -v *.log "/mnt/home/$USERNAME/" || echo "WARNING: Could not copy logs to /mnt/home/$USERNAME. Check permissions or path." >&2
else
    echo "WARNING: User home directory /mnt/home/$USERNAME does not exist. Logs not copied." >&2
fi
echo -ne "--- Log copying complete ---\n"

echo -ne "
-------------------------------------------------------------------------
 ▄▀█ █▀█ █▀▀ █░█ █▀▀ █▄░█ █░█ ▄▀█ █▄░█ █▀▀ █▀▀ █▀▄ █ █▄░█ █▀
 █▀█ █▀▄ █▄▄ █▀█ ██▄ █░▀█ █▀█ █▀█ █░▀█ █▄▄ ██▄ █▄▀ █ █░▀█ ▄█
-------------------------------------------------------------------------
                    Automated Arch Linux Installer
-------------------------------------------------------------------------
                Done - Please Eject Install Media and Reboot
"
