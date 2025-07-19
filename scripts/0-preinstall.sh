#!/usr/bin/env bash
set -euo pipefail # Crucial for error handling

log_file="/var/log/arch_preinstall.log" # Dedicated log for this script
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$log_file"
}
error_exit() {
    log_message "FATAL ERROR: $1" >&2
    echo "Installation failed at pre-install stage. Check $log_file for details." >&2
    exit 1
}
check_command() {
    "$@" # Execute the passed command(s)
    local status=$?
    if [ $status -ne 0 ]; then
        error_exit "Command '$*' failed with status $status."
    fi
}

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
-------------------------------------------------------------------------

Setting up mirrors for optimal download
"

log_message "Sourcing configuration from $CONFIGS_DIR/setup.conf"
if [[ ! -f "$CONFIGS_DIR/setup.conf" ]]; then
    error_exit "Configuration file '$CONFIGS_DIR/setup.conf' not found!"
fi
source "$CONFIGS_DIR/setup.conf" # DISK, FS, MOUNT_OPTIONS, LUKS_PASSWORD (if applicable)


if [[ -z "${DISK}" ]]; then error_exit "DISK variable not set in setup.conf!"; fi
if [[ -z "${FS}" ]]; then error_exit "FS variable not set in setup.conf!"; fi

log_message "Determining country ISO for reflector..."
iso=$(curl -4 -s ifconfig.co/country-iso)
if [ -z "$iso" ]; then
    log_message "WARNING: Could not determine country ISO via ifconfig.co. Falling back to 'US'."
    iso="US" # Fallback if curl fails or returns empty
fi

log_message "Setting system clock via NTP..."
check_command timedatectl set-ntp true

log_message "Updating archlinux-keyring..."
check_command pacman -S --noconfirm archlinux-keyring

log_message "Installing pacman-contrib and terminus-font..."
check_command pacman -S --noconfirm --needed pacman-contrib terminus-font

log_message "Setting font to ter-v22b..."
check_command setfont ter-v22b

log_message "Enabling ParallelDownloads in pacman.conf..."
check_command sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

log_message "Installing reflector, rsync, grub and essential tools..."

PACKAGES_TO_INSTALL="reflector rsync grub gptfdisk btrfs-progs"
if [[ "${FS}" == "ext4" ]]; then
    PACKAGES_TO_INSTALL+=" e2fsprogs"
elif [[ "${FS}" == "luks" ]]; then
    PACKAGES_TO_INSTALL+=" cryptsetup" # Add cryptsetup for LUKS
fi
check_command pacman -S --noconfirm --needed ${PACKAGES_TO_INSTALL}

log_message "Backing up current mirrorlist..."
check_command cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup

echo -ne "
-------------------------------------------------------------------------
                    Setting up $iso mirrors for faster downloads
-------------------------------------------------------------------------
"
log_message "Running reflector to update mirrorlist for $iso..."

check_command reflector -a 48 -c "$iso" -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist

log_message "Creating /mnt directory if it doesn't exist..."
check_command mkdir -p /mnt # -p ensures no error if it exists

echo -ne "
-------------------------------------------------------------------------
                    Formating Disk ($DISK)
-------------------------------------------------------------------------
"
log_message "Ensuring all partitions on $DISK are unmounted..."

umount -A --recursive /mnt 2>/dev/null || true

log_message "Zapping and creating new GPT partition table on $DISK..."
check_command sgdisk -Z "$DISK" # zap all on disk
check_command sgdisk -a 2048 -o "$DISK" # new gpt disk 2048 alignment

log_message "Creating partitions on $DISK..."
check_command sgdisk -n 1::+1M --typecode=1:ef02 --change-name=1:'BIOSBOOT' "$DISK" # partition 1 (BIOS Boot Partition)
check_command sgdisk -n 2::+300M --typecode=2:ef00 --change-name=2:'EFIBOOT' "$DISK" # partition 2 (UEFI Boot Partition)
check_command sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' "$DISK" # partition 3 (Root)

if [[ ! -d "/sys/firmware/efi" ]]; then # Checking for bios system
    log_message "Detected BIOS system. Setting BIOS bootable flag on partition 1."
    check_command sgdisk -A 1:set:2 "$DISK"
fi
log_message "Rereading partition table on $DISK..."
check_command partprobe "$DISK" # reread partition table to ensure it is correct


if [[ "${DISK}" =~ "nvme" ]]; then
    partition2="${DISK}p2"
    partition3="${DISK}p3"
else
    partition2="${DISK}2"
    partition3="${DISK}3"
fi
log_message "EFI partition: $partition2, Root partition: $partition3"

echo -ne "
-------------------------------------------------------------------------
                    Creating Filesystems
-------------------------------------------------------------------------
"


createsubvolumes () {
    log_message "Creating BTRFS subvolumes: @ @home @var @tmp @.snapshots"
    check_command btrfs subvolume create /mnt/@
    check_command btrfs subvolume create /mnt/@home
    check_command btrfs subvolume create /mnt/@var
    check_command btrfs subvolume create /mnt/@tmp
    check_command btrfs subvolume create /mnt/@.snapshots
}


mountallsubvol () {
    log_message "Mounting BTRFS subvolumes..."
    check_command mount -o "${MOUNT_OPTIONS}",subvol=@home "${partition3}" /mnt/home
    check_command mount -o "${MOUNT_OPTIONS}",subvol=@tmp "${partition3}" /mnt/tmp
    check_command mount -o "${MOUNT_OPTIONS}",subvol=@var "${partition3}" /mnt/var
    check_command mount -o "${MOUNT_OPTIONS}",subvol=@.snapshots "${partition3}" /mnt/.snapshots
}


subvolumesetup () {
    log_message "Performing BTRFS subvolume setup."
    # create nonroot subvolumes
    createsubvolumes
    
    log_message "Unmounting /mnt to remount with @ subvolume..."
    check_command umount /mnt
   
    log_message "Mounting @ subvolume on /mnt..."
    check_command mount -o "${MOUNT_OPTIONS}",subvol=@ "${partition3}" /mnt
   
    log_message "Creating necessary directories for BTRFS subvolumes..."
    check_command mkdir -p /mnt/{home,var,tmp,.snapshots}
 
    mountallsubvol
}

log_message "Formatting partitions with selected filesystem: ${FS}"
if [[ "${FS}" == "btrfs" ]]; then
    log_message "Formatting EFIBOOT ($partition2) as FAT32..."
    check_command mkfs.vfat -F32 -n "EFIBOOT" "${partition2}"
    log_message "Formatting ROOT ($partition3) as BTRFS..."
    check_command mkfs.btrfs -L ROOT "${partition3}" -f
    log_message "Mounting ROOT BTRFS on /mnt..."
    check_command mount -t btrfs "${partition3}" /mnt
    subvolumesetup
elif [[ "${FS}" == "ext4" ]]; then
    log_message "Formatting EFIBOOT ($partition2) as FAT32..."
    check_command mkfs.vfat -F32 -n "EFIBOOT" "${partition2}"
    log_message "Formatting ROOT ($partition3) as EXT4..."
    check_command mkfs.ext4 -L ROOT "${partition3}"
    log_message "Mounting ROOT EXT4 on /mnt..."
    check_command mount -t ext4 "${partition3}" /mnt
elif [[ "${FS}" == "luks" ]]; then
    log_message "Formatting EFIBOOT ($partition2) as FAT32..."
    check_command mkfs.vfat -F32 -n "EFIBOOT" "${partition2}"
    
    log_message "Encrypting ROOT ($partition3) with LUKS. WARNING: Password will be in logs if setup.conf is public."
    # WARNING: THIS IS HIGHLY INSECURE FOR PRODUCTION. User interactive input is recommended.
    # For automated builds, ensure LUKS_PASSWORD is NOT in publicly accessible setup.conf or logs.
    echo -n "${LUKS_PASSWORD}" | check_command cryptsetup -y -v luksFormat "${partition3}" -
    
    log_message "Opening LUKS container..."
    echo -n "${LUKS_PASSWORD}" | check_command cryptsetup open "${partition3}" ROOT -
    
    log_message "Formatting opened LUKS container as BTRFS..."
    # Note: Your script implies LUKS only works with BTRFS here.
    check_command mkfs.btrfs -L ROOT /dev/mapper/ROOT # Format the opened device, not raw partition
    
    log_message "Mounting LUKS-encrypted BTRFS on /mnt..."
    check_command mount -t btrfs /dev/mapper/ROOT /mnt # Mount the opened device
    subvolumesetup
    
    log_message "Storing UUID of encrypted partition for GRUB configuration."
    # Ensure this writes to the correct setup.conf path for post-setup scripts
    ENCRYPTED_PARTITION_UUID=$(blkid -s UUID -o value "${partition3}")
    echo "ENCRYPTED_PARTITION_UUID=$ENCRYPTED_PARTITION_UUID" >> "$CONFIGS_DIR/setup.conf"
fi

log_message "Creating /mnt/boot/efi directory..."
check_command mkdir -p /mnt/boot/efi
log_message "Mounting EFIBOOT partition on /mnt/boot/efi..."
check_command mount -t vfat -L EFIBOOT /mnt/boot/efi

log_message "Verifying root filesystem is mounted on /mnt..."
if ! grep -qs '/mnt' /proc/mounts; then
    error_exit "Root drive is not mounted at /mnt. Cannot continue."
fi

echo -ne "
-------------------------------------------------------------------------
                    Arch Install on Main Drive
-------------------------------------------------------------------------
"
log_message "Running pacstrap to install base system..."
check_command pacstrap /mnt base base-devel linux linux-firmware vim nano sudo archlinux-keyring wget libnewt

log_message "Adding keyserver to pacman.d/gnupg/gpg.conf..."
# Using '>>' means it will append. If the file doesn't exist, it might create it, but ensure directory exists.
check_command echo "keyserver hkp://keyserver.ubuntu.com" >> /mnt/etc/pacman.d/gnupg/gpg.conf

log_message "Copying ArchEnhancedINS scripts to /mnt/root/ArchEnhancedINS..."
# This is crucial for later chroot steps.
check_command cp -R "${SCRIPT_DIR}" /mnt/root/ArchEnhancedINS

log_message "Copying mirrorlist to new system's pacman directory..."
check_command cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist

log_message "Generating /etc/fstab..."
check_command genfstab -L /mnt >> /mnt/etc/fstab

echo "Generated /etc/fstab:"
cat /mnt/etc/fstab

echo -ne "
-------------------------------------------------------------------------
                    GRUB BIOS Bootloader Install & Check
-------------------------------------------------------------------------
"
if [[ ! -d "/sys/firmware/efi" ]]; then
    log_message "Detected BIOS system. Installing GRUB to $DISK."
    check_command grub-install --boot-directory=/mnt/boot "$DISK"
else
    log_message "Detected EFI system. Installing efibootmgr."
    check_command pacstrap /mnt efibootmgr --noconfirm --needed
fi

echo -ne "
-------------------------------------------------------------------------
                    Checking for low memory systems (<8GB) for swap
-------------------------------------------------------------------------
"
TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
if [[ "$TOTAL_MEM" -lt 8000000 ]]; then
    log_message "Low memory detected ($((TOTAL_MEM / 1024)) MB). Creating 2GB swapfile."
    log_message "Creating /mnt/opt/swap directory and setting NOCOW attribute for BTRFS."
    check_command mkdir -p /mnt/opt/swap
    check_command chattr +C /mnt/opt/swap # apply NOCOW, btrfs needs that.
    
    log_message "Creating swapfile at /mnt/opt/swap/swapfile (2GB)..."
    # dd status=progress only works in newer dd versions. Use 'status=noxfer' or remove if causing issues.
    check_command dd if=/dev/zero of=/mnt/opt/swap/swapfile bs=1M count=2048 status=progress
    
    log_message "Setting permissions for swapfile."
    check_command chmod 600 /mnt/opt/swap/swapfile # set permissions.
    check_command chown root /mnt/opt/swap/swapfile
    
    log_message "Making and enabling swapfile."
    check_command mkswap /mnt/opt/swap/swapfile
    check_command swapon /mnt/opt/swap/swapfile
    
    log_message "Adding swapfile to /mnt/etc/fstab."
    check_command echo "/opt/swap/swapfile       none    swap    sw      0       0" >> /mnt/etc/fstab
else
    log_message "Sufficient memory detected ($((TOTAL_MEM / 1024)) MB). Skipping swapfile creation."
fi

echo -ne "
-------------------------------------------------------------------------
                    SYSTEM READY FOR 1-setup.sh
-------------------------------------------------------------------------
"
