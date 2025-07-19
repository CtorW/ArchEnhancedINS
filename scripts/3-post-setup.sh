#!/usr/bin/env bash
set -euo pipefail # Crucial for error handling

log_file="/var/log/arch_post_setup.log" # Dedicated log for this script
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$log_file"
}
error_exit() {
    log_message "FATAL ERROR: $1" >&2
    echo "Installation failed at post-setup stage. Check $log_file for details." >&2
    exit 1
}
check_command() {
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        error_exit "Command '$*' failed with status $status."
    fi
}

# Define paths. $HOME is /root inside chroot.
SCRIPTHOME="$HOME/ArchEnhancedINS"
CONFIGS_DIR="$SCRIPTHOME/configs"

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

Final Setup and Configurations
GRUB EFI Bootloader Install & Check
"
log_message "Sourcing configuration from $CONFIGS_DIR/setup.conf..."
if [[ ! -f "$CONFIGS_DIR/setup.conf" ]]; then
    error_exit "Configuration file '$CONFIGS_DIR/setup.conf' not found in post-setup context!"
fi
source "$CONFIGS_DIR/setup.conf"

if [[ -z "${DISK}" ]]; then error_exit "DISK variable not set in setup.conf!"; fi
if [[ -z "${FS}" ]]; then error_exit "FS variable not set in setup.conf!"; fi
if [[ -z "${DESKTOP_ENV}" ]]; then error_exit "DESKTOP_ENV variable not set in setup.conf!"; fi
if [[ -z "${INSTALL_TYPE}" ]]; then error_exit "INSTALL_TYPE variable not set in setup.conf!"; fi
if [[ "$FS" == "luks" && -z "${ENCRYPTED_PARTITION_UUID}" ]]; then error_exit "ENCRYPTED_PARTITION_UUID not set for LUKS filesystem!"; fi
if [[ -z "${USERNAME}" ]]; then error_exit "USERNAME variable not set in setup.conf!"; fi


if [[ -d "/sys/firmware/efi" ]]; then
    log_message "Detected EFI system. Installing GRUB to EFI System Partition at /boot/efi."
    check_command grub-install --efi-directory=/boot/efi --target=x86_64-efi --bootloader-id=ArchLinux --recheck "$DISK"
else
    log_message "Detected BIOS system. GRUB was installed in 0-preinstall.sh. Skipping grub-install here."
fi

echo -ne "
-------------------------------------------------------------------------
                    Creating (and Theming) Grub Boot Menu
-------------------------------------------------------------------------
"
log_message "Configuring GRUB kernel parameters."
if [[ "${FS}" == "luks" ]]; then
    log_message "Adding LUKS decryption parameters to GRUB_CMDLINE_LINUX_DEFAULT."
    # Use % as delimiter in sed to avoid issues with / in paths/UUIDs
    check_command sed -i "s%GRUB_CMDLINE_LINUX_DEFAULT=\"%GRUB_CMDLINE_LINUX_DEFAULT=\"cryptdevice=UUID=${ENCRYPTED_PARTITION_UUID}:ROOT root=/dev/mapper/ROOT %g" /etc/default/grub
fi
log_message "Adding 'splash' parameter to GRUB_CMDLINE_LINUX_DEFAULT."
check_command sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="[^"]*/& splash /' /etc/default/grub

log_message "Installing CyberRe Grub theme..."
THEME_DIR="/boot/grub/themes"
THEME_NAME="CyberRe"
log_message "Creating the theme directory: ${THEME_DIR}/${THEME_NAME}"
check_command mkdir -p "${THEME_DIR}/${THEME_NAME}"

log_message "Copying the theme files from ${SCRIPTHOME}/configs${THEME_DIR}/${THEME_NAME}."
if [[ ! -d "${SCRIPTHOME}/configs${THEME_DIR}/${THEME_NAME}" ]]; then
    error_exit "GRUB theme source directory not found: ${SCRIPTHOME}/configs${THEME_DIR}/${THEME_NAME}"
fi
check_command cp -a "${SCRIPTHOME}/configs${THEME_DIR}/${THEME_NAME}/." "${THEME_DIR}/${THEME_NAME}/" # Copy contents, not the directory itself

log_message "Backing up Grub config to /etc/default/grub.bak..."
check_command cp -an /etc/default/grub /etc/default/grub.bak

log_message "Setting the CyberRe theme as the default in /etc/default/grub."
check_command sed -i '/^GRUB_THEME=/d' /etc/default/grub || true # `|| true` to not fail if line doesn't exist
check_command echo "GRUB_THEME=\"${THEME_DIR}/${THEME_NAME}/theme.txt\"" >> /etc/default/grub

log_message "Updating grub configuration (grub-mkconfig -o /boot/grub/grub.cfg)..."
check_command grub-mkconfig -o /boot/grub/grub.cfg
log_message "GRUB configuration updated."

echo -ne "
-------------------------------------------------------------------------
                    Enabling (and Theming) Login Display Manager
-------------------------------------------------------------------------
"
if [[ "${DESKTOP_ENV}" == "kde" ]]; then
    log_message "KDE desktop environment detected. Enabling SDDM service."
    check_command systemctl enable sddm.service
    if [[ "${INSTALL_TYPE}" == "FULL" ]]; then
        log_message "Full installation. Applying Nordic theme to SDDM."

        if grep -q "^[Theme]" /etc/sddm.conf; then
            check_command sed -i '/^[Theme]/aCurrent=Nordic' /etc/sddm.conf
        else
            check_command echo -e "[Theme]\nCurrent=Nordic" >> /etc/sddm.conf
        fi
        log_message "SDDM theme set to Nordic. Ensure Nordic theme is installed in /usr/share/sddm/themes/."
    fi
elif [[ "${DESKTOP_ENV}" == "gnome" ]]; then
    log_message "GNOME desktop environment detected. Enabling GDM service."
    check_command systemctl enable gdm.service
else
    if [[ ! "${DESKTOP_ENV}" == "server" ]]; then
        log_message "No specific DE detected or server install. Installing and enabling LightDM."
        # Removed sudo as script runs as root
        check_command pacman -S --noconfirm --needed lightdm lightdm-gtk-greeter
        check_command systemctl enable lightdm.service
    else
        log_message "Server desktop environment detected. Skipping display manager setup."
    fi
fi

echo -ne "
-------------------------------------------------------------------------
                    Enabling Essential Services
-------------------------------------------------------------------------
"
log_message "Enabling Cups service..."
check_command systemctl enable cups.service

log_message "Synchronizing NTP and enabling NTPD service..."
check_command ntpd -qg || log_message "ntpd -qg failed, continuing..." # ntpd -qg can sometimes fail if network isn't fully up yet, but not critical to stop
check_command systemctl enable ntpd.service

log_message "Disabling and stopping dhcpcd service (NetworkManager preferred)."
check_command systemctl disable dhcpcd.service || true # Disable might fail if not enabled, so make it non-fatal
check_command systemctl stop dhcpcd.service || true # Stop might fail if not running, so make it non-fatal

log_message "Enabling NetworkManager service (already done in 1-setup.sh, but good to re-confirm)."
check_command systemctl enable NetworkManager.service

log_message "Enabling Bluetooth service..."
check_command systemctl enable bluetooth.service # Use .service suffix for clarity

log_message "Enabling Avahi-daemon service..."
check_command systemctl enable avahi-daemon.service

if [[ "${FS}" == "luks" || "${FS}" == "btrfs" ]]; then
    echo -ne "
-------------------------------------------------------------------------
                    Creating Snapper Config
-------------------------------------------------------------------------
"
    log_message "Configuring Snapper for BTRFS/LUKS filesystem."
    SNAPPER_ROOT_CONFIG_SRC="${SCRIPTHOME}/configs/etc/snapper/configs/root"
    SNAPPER_CONF_D_SRC="${SCRIPTHOME}/configs/etc/conf.d/snapper"

    log_message "Creating /etc/snapper/configs/ directory."
    check_command mkdir -p /etc/snapper/configs/
    if [[ ! -f "$SNAPPER_ROOT_CONFIG_SRC" ]]; then
        error_exit "Snapper root config source file not found: $SNAPPER_ROOT_CONFIG_SRC"
    fi
    log_message "Copying Snapper root config from $SNAPPER_ROOT_CONFIG_SRC."
    check_command cp -rfv "$SNAPPER_ROOT_CONFIG_SRC" /etc/snapper/configs/

    log_message "Creating /etc/conf.d/ directory."
    check_command mkdir -p /etc/conf.d/
    if [[ ! -f "$SNAPPER_CONF_D_SRC" ]]; then
        error_exit "Snapper conf.d source file not found: $SNAPPER_CONF_D_SRC"
    fi
    log_message "Copying Snapper conf.d from $SNAPPER_CONF_D_SRC."
    check_command cp -rfv "$SNAPPER_CONF_D_SRC" /etc/conf.d/
else
    log_message "Filesystem is not LUKS or BTRFS. Skipping Snapper configuration."
fi

echo -ne "
-------------------------------------------------------------------------
                    Enabling (and Theming) Plymouth Boot Splash
-------------------------------------------------------------------------
"
log_message "Configuring Plymouth boot splash."
PLYMOUTH_THEMES_DIR_SRC="${SCRIPTHOME}/configs/usr/share/plymouth/themes"
PLYMOUTH_THEME="arch-glow" # Ensure this theme is available in the source dir

log_message "Creating /usr/share/plymouth/themes directory."
check_command mkdir -p /usr/share/plymouth/themes

log_message "Copying Plymouth theme '${PLYMOUTH_THEME}' to /usr/share/plymouth/themes."
if [[ ! -d "${PLYMOUTH_THEMES_DIR_SRC}/${PLYMOUTH_THEME}" ]]; then
    error_exit "Plymouth theme source directory not found: ${PLYMOUTH_THEMES_DIR_SRC}/${PLYMOUTH_THEME}"
fi
check_command cp -rf "${PLYMOUTH_THEMES_DIR_SRC}/${PLYMOUTH_THEME}" /usr/share/plymouth/themes

log_message "Modifying /etc/mkinitcpio.conf for Plymouth hooks."
check_command sed -i 's/HOOKS=(base udev/HOOKS=(base udev plymouth/' /etc/mkinitcpio.conf

if [[ "$FS" == "luks" ]]; then
    log_message "Adding 'plymouth-encrypt' hook after 'encrypt' for LUKS setup."
    # This sed command assumes 'encrypt' hook is already present in mkinitcpio.conf
    # and adds 'plymouth-encrypt' right after it.
    check_command sed -i 's/encrypt/encrypt plymouth-encrypt/' /etc/mkinitcpio.conf
else
    log_message "Skipping 'plymouth-encrypt' hook as FS is not LUKS."
fi

log_message "Setting default Plymouth theme to '${PLYMOUTH_THEME}' and rebuilding initramfs."
check_command plymouth-set-default-theme -R "$PLYMOUTH_THEME"
log_message "Plymouth theme installed and initramfs rebuilt."

echo -ne "
-------------------------------------------------------------------------
                    Cleaning Up
-------------------------------------------------------------------------
"
log_message "Removing NOPASSWD from sudoers and enabling password requirement for wheel group."
check_command sed -i 's/^%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
check_command sed -i 's/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers
check_command sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
check_command sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

log_message "Removing installer files from root's home directory."
check_command rm -rf "$HOME/ArchEnhancedINS"

log_message "Removing installer files from user's home directory."
if [[ -n "$USERNAME" && -d "/home/$USERNAME/ArchEnhancedINS" ]]; then
    check_command rm -rf "/home/$USERNAME/ArchEnhancedINS"
else
    log_message "Skipping removal of /home/$USERNAME/ArchEnhancedINS: USERNAME not set or directory not found."
fi

log_message "Post-setup complete. System is ready for reboot."
