<div align="center">
  <br><br>
  <img src="https://github.com/user-attachments/assets/5ea9f193-e984-4589-a865-79fac480abb5" alt="ArchEnhancedINS Logo/Banner" width="600"/>
  <br><br>
  <a href="https://git.io/typing-svg">
    <img src="https://readme-typing-svg.demolab.com?font=Fira+Code&pause=1000&color=000000&center=true&vCenter=true&width=435&lines=Credit+Christitustech;Arch+Installer;ArchEnhancedINS;Modified+by+CtorW" alt="Typing SVG"/>
  </a>
</div>

---
> [!CAUTION]
> ## ⚠️ **Critical Disclaimer: Data Loss Warning**
>
> **This script performs a complete format of your selected hard drive, which will erase ALL data stored on it, rendering it unrecoverable by standard means.**
>
> **BEFORE PROCEEDING, IT IS ABSOLUTELY CRITICAL THAT YOU:**
>
> 1. **Back up all essential data:** This includes documents, photos, videos, music, applications, and any other files you wish to keep. **Once the format is complete, these files will be permanently gone.**
> 2. **Double-check the target drive:** Ensure you have selected the **correct drive** for formatting. Formatting the wrong drive will result in catastrophic data loss.
> 3. **Understand the consequences:** Formatting is a **destructive process**. It is typically used when preparing a drive for a fresh operating system installation, troubleshooting serious drive errors, or securely erasing data.
>
> I, the developer, am **not responsible** for any data loss, system instability, or other issues that may arise from using this script. **You are proceeding entirely at your own risk.** While guidance is offered, the ultimate responsibility for your actions and their consequences lies with you.
>
> **Please proceed with extreme caution and only if you fully understand the implications.** Failure to do so could result in significant data loss and system problems.

---

## Getting Started: Arch Linux Live Environment Setup

Before running the installer, you need to prepare your Arch Linux live environment.

### 1. Internet Connection (Wi-Fi Example)

If you're using Wi-Fi, connect to your network using `iwctl`:

```bash
iwctl
station wlan0 connect <YOUR_WIFI_SSID>
# Enter your Wi-Fi password when prompted.
exit
```
### 2. Initialize Pacman Keys

Ensure your package manager is ready for secure package downloads:
```bash
pacman-key --init
pacman-key --populate archlinux
```
### 3. Install Git

Git is required to clone the installer repository:
```bash
pacman -Syy git --noconfirm
```
### 💻 How to Install ArchEnhancedINS

Once your live environment is set up and you have an internet connection:
```bash
git clone https://github.com/CtorW/ArchEnhancedINS.git
cd ArchEnhancedINS
chmod +x ArchEnhancnedINS.sh
./ArchEnhancnedINS.sh
```
### ✅ After Installation

💾 Eject USB/Installation Media

🔁 Reboot your system

✨ Coming Soon: Hyprland with Dotfiles Integration! ✨

    Hyprland Preview

Stay tuned for more desktop environment options and enhanced customization!
