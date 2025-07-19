#!/usr/bin/env bash
set -euo pipefail

log_file="/var/log/arch_setup.log"
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$log_file"
}
error_exit() {
    log_message "FATAL ERROR: $1" >&2
    echo "Installation failed at setup stage. Check $log_file for details." >&2
    exit 1
}
check_command() {
    log_message "Executing: $*"
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        error_exit "Command '$*' failed with status $status."
    fi
}

CONFIGS_DIR="$HOME/ArchEnhancedINS/configs"
SCRIPTS_DIR="$HOME/ArchEnhancedINS/scripts"
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
log_message "Enabling and starting NetworkManager service..."
check_command systemctl enable --now NetworkManager.service

echo -ne "
-------------------------------------------------------------------------
                  Setting up mirrors for optimal download
-------------------------------------------------------------------------
"
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
if [[ "$TOTAL_MEM_KB" -gt 8000000 ]]; then
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
                  Installing Base System Packages & Desktop Environment
-------------------------------------------------------------------------
"
ALL_PACKAGES_TO_INSTALL=()

PACMAN_PKGS_FILE="$PKG_FILES_DIR/pacman-pkgs.txt"
if [[ -f "$PACMAN_PKGS_FILE" ]]; then
    log_message "Reading base packages from: $PACMAN_PKGS_FILE"
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -z "$line" ]]; then continue; fi
        ALL_PACKAGES_TO_INSTALL+=("$line")
    done < "$PACMAN_PKGS_FILE"
    log_message "Added ${#ALL_PACKAGES_TO_INSTALL[@]} base packages from pacman-pkgs.txt."
else
    error_exit "Base Pacman package list '$PACMAN_PKGS_FILE' not found! This file is essential."
fi

if [[ -z "${DESKTOP_ENV+x}" ]]; then
    error_exit "DESKTOP_ENV is not set in setup.conf. Cannot determine desktop environment packages."
fi

DE_PKG_FILE="$PKG_FILES_DIR/$DESKTOP_ENV.txt"
if [[ ! -f "$DE_PKG_FILE" ]]; then
    if [[ "$DESKTOP_ENV" == "server" ]]; then
        log_message "DESKTOP_ENV is 'server'. No additional DE-specific packages will be installed (assuming server.txt is empty or doesn't exist)."
    else
        error_exit "Desktop Environment package list '$DE_PKG_FILE' not found for '$DESKTOP_ENV'. Please create it."
    fi
else
    log_message "Reading packages for selected desktop environment ($DESKTOP_ENV) from: $DE_PKG_FILE"

    declare -a MINIMAL_DE_PACKAGES=()
    declare -a FULL_DE_PACKAGES=()
    SEPARATOR_FOUND=false

    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [[ -z "$line" ]]; then continue; fi

        if [[ "$line" == "--END OF MINIMAL INSTALL--" ]]; then
            SEPARATOR_FOUND=true
            log_message "Separator '--END OF MINIMAL INSTALL--' found in $DE_PKG_FILE."
            continue
        fi

        if [[ "$SEPARATOR_FOUND" == false ]]; then
            MINIMAL_DE_PACKAGES+=("$line")
        else
            FULL_DE_PACKAGES+=("$line")
        fi
    done < "$DE_PKG_FILE"

    ALL_PACKAGES_TO_INSTALL+=("${MINIMAL_DE_PACKAGES[@]}")
    log_message "Added ${#MINIMAL_DE_PACKAGES[@]} minimal packages for $DESKTOP_ENV."

    if [[ "${INSTALL_TYPE}" == "FULL" ]]; then
        log_message "INSTALL_TYPE is FULL. Adding ${#FULL_DE_PACKAGES[@]} additional packages for $DESKTOP_ENV."
        ALL_PACKAGES_TO_INSTALL+=("${FULL_DE_PACKAGES[@]}")
    elif [[ "${INSTALL_TYPE}" == "MINIMAL" ]]; then
        log_message "INSTALL_TYPE is MINIMAL. Skipping additional full packages for $DESKTOP_ENV."
    else
        log_message "WARNING: Unknown INSTALL_TYPE '${INSTALL_TYPE}'. Defaulting to MINIMAL for DE-specific packages."
    fi
fi

if [[ ${#ALL_PACKAGES_TO_INSTALL[@]} -eq 0 ]]; then
    log_message "No packages collected for installation. This might indicate an error or empty package lists."
else
    log_message "Initiating Pacman installation for a total of ${#ALL_PACKAGES_TO_INSTALL[@]} unique packages."
    check_command pacman -S --noconfirm --needed "${ALL_PACKAGES_TO_INSTALL[@]}"
    log_message "Pacman installation completed successfully for all collected packages."
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
    check_command pacman -S --noconfirm --needed nvidia-dkms nvidia-utils lib32-nvidia-utils opencl-nvidia
elif lspci | grep -q 'VGA' | grep -qE "Radeon|AMD"; then
    log_message "AMD Radeon GPU detected. Installing AMDGPU drivers (mesa, vulkan-radeon)."
    check_command pacman -S --noconfirm --needed mesa vulkan-radeon lib32-mesa lib32-vulkan-radeon
elif grep -qE "Integrated Graphics Controller|Intel Corporation UHD" <<< "${gpu_type}"; then
    log_message "Intel Integrated GPU detected. Installing Intel graphics drivers (mesa, vulkan-intel)."
    check_command pacman -S --noconfirm --needed mesa vulkan-intel lib32-mesa lib32-vulkan-intel intel-media-driver
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
    groupadd libvirt 2>/dev/null || log_message "libvirt group already exists or could not be created, skipping creation."

    log_message "Creating user '$USERNAME' and adding to wheel and libvirt groups."

    check_command useradd -m -G wheel,libvirt -s /bin/bash "$USERNAME"

    log_message "Setting password for user '$USERNAME'..."
    printf "%s:%s\n" "$USERNAME" "$PASSWORD" | check_command chpasswd
    log_message "User '$USERNAME' and password set."

    log_message "Copying ArchEnhancedINS installer files to user's home directory..."
    check_command cp -R "$INSTALLER_ROOT" "/home/$USERNAME/ArchEnhancedINS"
    check_command chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/ArchEnhancedINS"
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
    check_command sed -i 's/^HOOKS=\(.*\)\sfilesystems\s\(.*\)/HOOKS=\1 keyboard keymap encrypt filesystems \2/' /etc/mkinitcpio.conf
    if ! grep -q "encrypt" /etc/mkinitcpio.conf; then
        check_command sed -i 's/\(HOOKS=".*\)filesystems/\1keyboard keymap encrypt filesystems/' /etc/mkinitcpio.conf
    fi

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
