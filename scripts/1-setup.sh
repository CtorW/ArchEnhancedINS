#!/usr/bin/env bash
set -euo pipefail # Crucial for error handling

log_file="/var/log/arch_setup.log" # Dedicated log for this script
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$log_file"
}
error_exit() {
    log_message "FATAL ERROR: $1" >&2
    echo "Installation failed at setup stage. Check $log_file for details." >&2
    exit 1
}
check_command() {
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        error_exit "Command '$*' failed with status $status."
    fi
}

CONFIGS_DIR="$HOME/ArchEnhancedINS/configs"
SCRIPTS_DIR="$HOME/ArchEnhancedINS/scripts" # Needed for copying user scripts later
PKG_FILES_DIR="$HOME/ArchEnhancedINS/pkg-files"

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
                                                                                                                                                          
                                                                                                                                                          
-------------------------------------------------------------------------
                    Automated Arch Linux Installer
                      SCRIPTHOME: ArchEnhancedINS
-------------------------------------------------------------------------
"
log_message "Sourcing configuration from $CONFIGS_DIR/setup.conf"
if [[ ! -f "$CONFIGS_DIR/setup.conf" ]]; then
    error_exit "Configuration file '$CONFIGS_DIR/setup.conf' not found inside chroot!"
fi
source "$CONFIGS_DIR/setup.conf"

if [[ -z "${USERNAME}" ]]; then error_exit "USERNAME variable not set in setup.conf!"; fi
if [[ -z "${PASSWORD}" ]]; then error_exit "PASSWORD variable not set in setup.conf!"; fi
if [[ -z "${NAME_OF_MACHINE}" ]]; then error_exit "NAME_OF_MACHINE variable not set in setup.conf!"; fi
if [[ -z "${TIMEZONE}" ]]; then error_exit "TIMEZONE variable not set in setup.conf!"; fi
if [[ -z "${KEYMAP}" ]]; then error_exit "KEYMAP variable not set in setup.conf!"; fi
if [[ -z "${DESKTOP_ENV}" ]]; then error_exit "DESKTOP_ENV variable not set in setup.conf!"; fi
if [[ -z "${INSTALL_TYPE}" ]]; then error_exit "INSTALL_TYPE variable not set in setup.conf!"; fi
if [[ -z "${FS}" ]]; then error_exit "FS variable not set in setup.conf!"; fi


echo -ne "
-------------------------------------------------------------------------
                    Network Setup
-------------------------------------------------------------------------
"
log_message "Installing NetworkManager and dhclient..."
check_command pacman -S --noconfirm --needed networkmanager dhclient

log_message "Enabling and starting NetworkManager service..."
check_command systemctl enable --now NetworkManager.service

echo -ne "
-------------------------------------------------------------------------
                    Setting up mirrors for optimal download
-------------------------------------------------------------------------
"
log_message "Installing pacman-contrib, curl, reflector, rsync, grub, git..."
check_command pacman -S --noconfirm --needed pacman-contrib curl reflector rsync grub arch-install-scripts git

log_message "Backing up current mirrorlist inside chroot..."
check_command cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak

log_message "Configuring makepkg.conf for optimal compilation and compression..."
nc=$(grep -c ^processor /proc/cpuinfo || echo 1) 
echo -ne "
-------------------------------------------------------------------------
                    You have ${nc} cores. Adjusting makeflags and compression.
-------------------------------------------------------------------------
"

log_message "Setting MAKEFLAGS=\"-j$nc\" in /etc/makepkg.conf"
check_command sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$nc\"/g" /etc/makepkg.conf

TOTAL_MEM_KB=$(grep -i 'memtotal' /proc/meminfo | awk '{print $2}')
if [[ "$TOTAL_MEM_KB" -gt 8000000 ]]; then # 8GB in KB
    log_message "Total memory ($((TOTAL_MEM_KB / 1024))MB) > 8GB. Setting XZ compression to use all cores."
    check_command sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T $nc -z -)/g" /etc/makepkg.conf
else
    log_message "Total memory ($((TOTAL_MEM_KB / 1024))MB) <= 8GB. Skipping parallel XZ compression."
fi

echo -ne "
-------------------------------------------------------------------------
                    Setup Language to US and set locale
-------------------------------------------------------------------------
"
log_message "Enabling en_US.UTF-8 locale..."
check_command sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen

log_message "Generating locales..."
check_command locale-gen

log_message "Setting timezone to ${TIMEZONE}..."
check_command timedatectl --no-ask-password set-timezone "${TIMEZONE}"

log_message "Enabling NTP synchronization..."
check_command timedatectl --no-ask-password set-ntp 1

log_message "Setting system locale to en_US.UTF-8..."
check_command localectl --no-ask-password set-locale LANG="en_US.UTF-8" LC_TIME="en_US.UTF-8"

log_message "Creating symlink for localtime..."
check_command ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime

log_message "Setting keymap to ${KEYMAP}..."
check_command localectl --no-ask-password set-keymap "${KEYMAP}"

log_message "Configuring sudoers for wheel group (NOPASSWD)..."
check_command sed -i 's/^# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
check_command sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers

log_message "Enabling ParallelDownloads in /etc/pacman.conf..."
check_command sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

log_message "Enabling Multilib repository in /etc/pacman.conf..."
check_command sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf

log_message "Synchronizing pacman databases with new mirrorlist and multilib enabled..."
check_command pacman -Sy --noconfirm --needed

echo -ne "
-------------------------------------------------------------------------
                    Installing Base System Packages
-------------------------------------------------------------------------
"
if [[ ! "$DESKTOP_ENV" == server ]]; then
    log_message "Starting package installation based on INSTALL_TYPE: ${INSTALL_TYPE}..."
    if [[ ! -f "$PKG_FILES_DIR/pacman-pkgs.txt" ]]; then
        error_exit "Package list file '$PKG_FILES_DIR/pacman-pkgs.txt' not found!"
    fi

    # Read packages line by line, handling INSTALL_TYPE
    # Changed `sudo pacman` to `pacman` as we are already root in chroot
    sed -n '/^'$INSTALL_TYPE'/,$p' "$PKG_FILES_DIR/pacman-pkgs.txt" | \
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | xargs) # Trim whitespace
        if [[ -z "$line" || "$line" =~ ^# ]]; then
            continue # Skip empty lines and comments
        fi
        if [[ "$line" == '--END OF MINIMAL INSTALL--' && "$INSTALL_TYPE" == "MINIMAL" ]]; then
            log_message "Reached end of MINIMAL installation type. Stopping package install loop."
            break # Stop reading further for MINIMAL install
        fi
        if [[ "$line" == '--END OF MINIMAL INSTALL--' && "$INSTALL_TYPE" == "FULL" ]]; then
            log_message "Skipping '--END OF MINIMAL INSTALL--' for FULL installation type."
            continue # Continue for FULL install
        fi
        
        log_message "INSTALLING: ${line}"
        check_command pacman -S --noconfirm --needed ${line}
    done
else
    log_message "DESKTOP_ENV is 'server'. Skipping additional package installation from pacman-pkgs.txt."
fi

echo -ne "
-------------------------------------------------------------------------
                    Installing Microcode
-------------------------------------------------------------------------
"
log_message "Detecting CPU type and installing microcode..."
proc_type=$(lscpu)
if grep -q "GenuineIntel" <<< "${proc_type}"; then
    log_message "Intel CPU detected. Installing intel-ucode."
    check_command pacman -S --noconfirm --needed intel-ucode
elif grep -q "AuthenticAMD" <<< "${proc_type}"; then
    log_message "AMD CPU detected. Installing amd-ucode."
    check_command pacman -S --noconfirm --needed amd-ucode
else
    log_message "Unknown CPU vendor. Skipping microcode installation."
fi

echo -ne "
-------------------------------------------------------------------------
                    Installing Graphics Drivers
-------------------------------------------------------------------------
"
log_message "Detecting GPU type and installing drivers..."
gpu_type=$(lspci)
if grep -qE "NVIDIA|GeForce" <<< "${gpu_type}"; then
    log_message "NVIDIA GPU detected. Installing nvidia-dkms and relevant packages."
    check_command pacman -S --noconfirm --needed nvidia-dkms nvidia-utils lib32-nvidia-utils opencl-nvidia # Recommended for flexibility
elif lspci | grep -q 'VGA' | grep -qE "Radeon|AMD"; then
    log_message "AMD Radeon GPU detected. Installing AMDGPU drivers (mesa, vulkan-radeon)."
    check_command pacman -S --noconfirm --needed mesa vulkan-radeon lib32-mesa lib32-vulkan-radeon # Modern AMD drivers
elif grep -qE "Integrated Graphics Controller|Intel Corporation UHD" <<< "${gpu_type}"; then
    log_message "Intel Integrated GPU detected. Installing Intel graphics drivers (mesa, vulkan-intel)."
    check_command pacman -S --noconfirm --needed mesa vulkan-intel lib32-mesa lib32-vulkan-intel intel-media-driver # Intel drivers
else
    log_message "No specific GPU type detected or supported by script. Skipping GPU driver installation."
    log_message "Consider manually installing drivers if graphics environment is desired."
fi

echo -ne "
-------------------------------------------------------------------------
                    Adding User
-------------------------------------------------------------------------
"
if [ "$(whoami)" = "root" ]; then
    log_message "Adding group 'libvirt'..."
    check_command groupadd libvirt || log_message "libvirt group already exists, skipping creation." # Handle existing group

    log_message "Creating user '$USERNAME' and adding to wheel and libvirt groups."
    
    check_command useradd -m -G wheel,libvirt -s /bin/bash "$USERNAME"

    log_message "Setting password for user '$USERNAME'..."
    printf "%s:%s\n" "$USERNAME" "$PASSWORD" | check_command chpasswd
    log_message "User '$USERNAME' and password set."

    log_message "Copying ArchEnhancedINS installer files to user's home directory..."
    check_command cp -R "$SCRIPTS_DIR/.." "/home/$USERNAME/ArchEnhancedINS" # Copy the parent directory (ArchEnhancedINS)
    check_command chown -R "$USERNAME:" "/home/$USERNAME/ArchEnhancedINS"
    log_message "ArchEnhancedINS copied to /home/$USERNAME/ArchEnhancedINS"

    log_message "Setting hostname to '${NAME_OF_MACHINE}'..."
    check_command echo "$NAME_OF_MACHINE" > /etc/hostname
    log_message "Hostname set."
else
    log_message "WARNING: Script not running as root. User creation and hostname setting skipped."
    log_message "If this is not intended, ensure 1-setup.sh is called with arch-chroot."
fi

if [[ "${FS}" == "luks" ]]; then
    log_message "LUKS detected. Configuring /etc/mkinitcpio.conf for encryption hook."
    log_message "Adding 'encrypt' hook before 'filesystems' in mkinitcpio.conf..."
    check_command sed -i '0,/filesystems/s/filesystems/encrypt filesystems/' /etc/mkinitcpio.conf
    
    log_message "Rebuilding mkinitcpio image with 'encrypt' hook and linux kernel."
    check_command mkinitcpio -p linux
else
    log_message "LUKS not selected. Skipping mkinitcpio configuration for encryption."
fi

echo -ne "
-------------------------------------------------------------------------
                    SYSTEM READY FOR 2-user.sh
-------------------------------------------------------------------------
"
