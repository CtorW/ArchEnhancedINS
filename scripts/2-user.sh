#!/usr/bin/env bash
set -euo pipefail # Crucial for error handling

log_file="$HOME/2-user.log" # User-specific log
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$log_file"
}
error_exit() {
    log_message "FATAL ERROR: $1" >&2
    echo "Installation failed at user setup stage. Check $log_file for details." >&2
    exit 1
}
check_command() {
    "$@"
    local status=$?
    if [ $status -ne 0 ]; then
        error_exit "Command '$*' failed with status $status."
    fi
}

SCRIPTHOME="$HOME/ArchEnhancedINS"
CONFIGS_DIR="$SCRIPTHOME/configs"
PKG_FILES_DIR="$SCRIPTHOME/pkg-files"

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

Installing AUR Softwares
"
log_message "Sourcing configuration from $CONFIGS_DIR/setup.conf..."
if [[ ! -f "$CONFIGS_DIR/setup.conf" ]]; then
    error_exit "Configuration file '$CONFIGS_DIR/setup.conf' not found in user context!"
fi
source "$CONFIGS_DIR/setup.conf"

if [[ -z "${USERNAME}" ]]; then error_exit "USERNAME variable not set in setup.conf!"; fi
if [[ -z "${INSTALL_TYPE}" ]]; then error_exit "INSTALL_TYPE variable not set in setup.conf!"; fi
if [[ -z "${DESKTOP_ENV}" ]]; then error_exit "DESKTOP_ENV variable not set in setup.conf!"; fi
if [[ -z "${AUR_HELPER}" ]]; then error_exit "AUR_HELPER variable not set in setup.conf!"; fi

log_message "Starting user-specific configurations for $USERNAME."

log_message "Setting up Zsh configurations and themes."
check_command cd "$HOME" # Ensure we are in the user's home directory

log_message "Creating .cache directory and zsh history file."
check_command mkdir -p "$HOME/.cache"
check_command touch "$HOME/.cache/zshhistory"

log_message "Cloning ChrisTitusTech/zsh repository."
if [[ -d "$HOME/zsh" ]]; then
    log_message "Existing $HOME/zsh detected, removing for fresh clone."
    check_command rm -rf "$HOME/zsh"
fi
check_command git clone "https://github.com/ChrisTitusTech/zsh" "$HOME/zsh"

log_message "Cloning romkatv/powerlevel10k repository."
if [[ -d "$HOME/powerlevel10k" ]]; then
    log_message "Existing $HOME/powerlevel10k detected, removing for fresh clone."
    check_command rm -rf "$HOME/powerlevel10k"
fi
check_command git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/powerlevel10k"

log_message "Creating symlink for .zshrc."
check_command ln -sf "$HOME/zsh/.zshrc" "$HOME/.zshrc"

log_message "Installing desktop environment specific packages from ${DESKTOP_ENV}.txt."
if [[ ! -f "$PKG_FILES_DIR/${DESKTOP_ENV}.txt" ]]; then
    error_exit "Desktop environment package list '$PKG_FILES_DIR/${DESKTOP_ENV}.txt' not found!"
fi

sed -n '/^'$INSTALL_TYPE'/,$p' "$PKG_FILES_DIR/${DESKTOP_ENV}.txt" | \
while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(echo "$line" | xargs) # Trim whitespace
    if [[ -z "$line" || "$line" =~ ^# ]]; then
        continue # Skip empty lines and comments
    fi
    if [[ "$line" == '--END OF MINIMAL INSTALL--' && "$INSTALL_TYPE" == "MINIMAL" ]]; then
        log_message "Reached end of MINIMAL installation type. Stopping pacman package install loop."
        break # Stop reading further for MINIMAL install
    fi
    if [[ "$line" == '--END OF MINIMAL INSTALL--' && "$INSTALL_TYPE" == "FULL" ]]; then
        log_message "Skipping '--END OF MINIMAL INSTALL--' for FULL installation type."
        continue # Continue for FULL install
    fi

    log_message "INSTALLING PACMAN PACKAGE: ${line}"
    check_command sudo pacman -S --noconfirm --needed ${line}
done

if [[ ! "$AUR_HELPER" == "none" ]]; then
    log_message "AUR_HELPER is set to '$AUR_HELPER'. Proceeding with AUR setup."
    log_message "Cloning AUR helper '$AUR_HELPER' repository."
    check_command cd "$HOME" # Ensure we are in home for cloning
    if [[ -d "$HOME/$AUR_HELPER" ]]; then
        log_message "Existing $HOME/$AUR_HELPER detected, removing for fresh clone."
        check_command rm -rf "$HOME/$AUR_HELPER"
    fi
    check_command git clone "https://aur.archlinux.org/$AUR_HELPER.git" "$HOME/$AUR_HELPER"

    log_message "Building and installing $AUR_HELPER."
    check_command cd "$HOME/$AUR_HELPER"
    check_command makepkg -si --noconfirm

    log_message "Installing AUR packages from aur-pkgs.txt using $AUR_HELPER."
    if [[ ! -f "$PKG_FILES_DIR/aur-pkgs.txt" ]]; then
        error_exit "AUR package list '$PKG_FILES_DIR/aur-pkgs.txt' not found!"
    fi

    sed -n '/^'$INSTALL_TYPE'/,$p' "$PKG_FILES_DIR/aur-pkgs.txt" | \
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=$(echo "$line" | xargs) # Trim whitespace
        if [[ -z "$line" || "$line" =~ ^# ]]; then
            continue # Skip empty lines and comments
        fi
        if [[ "$line" == '--END OF MINIMAL INSTALL--' && "$INSTALL_TYPE" == "MINIMAL" ]]; then
            log_message "Reached end of MINIMAL installation type. Stopping AUR package install loop."
            break # Stop reading further for MINIMAL install
        fi
        if [[ "$line" == '--END OF MINIMAL INSTALL--' && "$INSTALL_TYPE" == "FULL" ]]; then
            log_message "Skipping '--END OF MINIMAL INSTALL--' for FULL installation type."
            continue # Continue for FULL install
        fi

        log_message "INSTALLING AUR PACKAGE: ${line}"
        check_command "$AUR_HELPER" -S --noconfirm --needed "${line}"
    done
else
    log_message "AUR_HELPER is set to 'none'. Skipping AUR package installation."
fi

log_message "Exporting ~/.local/bin to PATH for current session."
export PATH="$PATH:$HOME/.local/bin" # Double quotes for robustness

if [[ "$INSTALL_TYPE" == "FULL" ]]; then
    log_message "Full installation detected. Applying desktop environment theming."
    if [[ "$DESKTOP_ENV" == "kde" ]]; then
        log_message "KDE desktop detected. Applying KDE configurations and Konsave setup."
        check_command mkdir -p "$HOME/.config"
        check_command cp -r "$SCRIPTHOME/configs/.config/"* "$HOME/.config/"

        log_message "Installing konsave via pip."
        # Ensure python-pip is installed in 1-setup.sh or pacman-pkgs.txt
        check_command pip install konsave

        log_message "Importing KDE Konsave profile."
        check_command konsave -i "$SCRIPTHOME/configs/kde.knsv"
        log_message "Activating KDE Konsave profile."
        sleep 1 # Give konsave a moment if needed
        check_command konsave -a kde
    else
        log_message "Theming for ${DESKTOP_ENV} is not implemented in this script."
    fi
else
    log_message "Installation type is not FULL. Skipping desktop environment theming."
fi

echo -ne "
-------------------------------------------------------------------------
                    SYSTEM READY FOR 3-post-setup.sh
-------------------------------------------------------------------------
"
exit 0
