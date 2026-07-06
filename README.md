# DOAN: Debian On Android Natively
![A Tab A9+ Running Debian](./media/20260704_000004.jpg.jpeg)


## ⚠️ Disclaimer
> - Only **Snapdragon** devices are supported.
> - This method has been specifically tested on only **Samsung Galaxy Tab A9+ (SM-X210)**.


## Prerequisites
Before you start:
1.  **GSI:** [Google's Android 16 Non-GMS GSI](https://dl.google.com/developers/android/baklava/images/gsi/aosp_arm64-exp-BP2A.250605.031.A3-13578795-82277143.zip) It is not compulsory, but it is recommended.
2.  **Root:** [Magisk](https://github.com/topjohnwu/Magisk) installed and functional.
3.  **Connection:** Internet connection on the device and an active ADB bridge from your PC.


## Automated Installation

| OS | Link |
| :--- | :--- |
| **Windows** | [DOAN-Setup-Windows.py](https://github.com/av2xn/DOAN/blob/main/DOAN-Setup-Windows.py) |
| **macOS** | [DOAN-Setup-macOS.command](https://github.com/av2xn/DOAN/blob/main/DOAN-Setup-macOS.command) |
| **Linux** | [DOAN-Setup-Linux.sh](https://github.com/av2xn/DOAN/blob/main/DOAN-Setup-Linux.sh) |


## How to use after installation
Connect your device via ADB and run the startup script directly:

```bash
adb shell "su -c '/data/local/tmp/script.sh'"
```

## ⚠️ Warning
> Sometimes you may need to reboot the device!
> If your screen only shows black, next time, run the script whilst the main screen is displayed
