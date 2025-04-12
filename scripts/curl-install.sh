#!/bin/bash

# Checking if is running in Repo Folder
if [[ "$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]')" =~ ^scripts$ ]]; then
    echo "You are running this in ArchEnhancedINS Folder."
    echo "Please use ./ArchEnhancedINS.sh instead"
    exit
fi

# Installing git

echo "Installing git."
pacman -Sy --noconfirm --needed git glibc

echo "Cloning the ArchEnhancedINS Project"
git clone https://github.com/christitustech/ArchEnhancedINS

echo "Executing ArchEnhancedINS Script"

cd $HOME/ArchEnhancedINS

exec ./ArchEnhancedINS.sh
