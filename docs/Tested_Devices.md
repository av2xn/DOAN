# Tested Devices

| Status Legend | Meaning |
| :---: | :--- |
| ✅ | Working |
| ❌ | Not working |

| Device & Model | Codename | ROM | Kernel | Root method | SoC | GPU | Screen | Touch |
| :--- | :---: | :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **Samsung Galaxy Tab A9+**<br>*(SM-X210)* | `gta9pwifi` | [Android 16 AOSP GSI](https://developer.android.com/about/versions/16/gsi-release-notes), [LinageOS 23.2 GSI (Unofficial)](https://sourceforge.net/projects/misterztr-gsi/files/LineageOS/Android%2016/LineageOS-23.2-20260524-VANILLA-EXT4-GSI.7z/download?use_mirror=netix&use_mirror=netix&r=https://github.com/) | 5.4 | Magisk, APatch | Qualcomm Snapdragon 695 5G | Adreno 619 | ✅ | ✅ |
| **OnePlus 15**<br>*(CPH2745)* | `infiniti` | OxygenOS 16 | 6.12 | KernelSU | Qualcomm Snapdragon 8 Elite Gen 5 | Adreno 840 | ✅ | ❌ |
| **Samsung Galaxy S24 Ultra**<br>*(SM-S928B)* | `e3q` | OneUI 7.0 | 6.1 | Magisk | Qualcomm Snapdragon 8 Gen 3 for Galaxy | Adreno 750 | ✅ | ❌ |
| **Nothing Phone 1**<br>*(A063)* | `spacewar` | NothingOS 3.2 | 5.4 | ? | Qualcomm Snapdragon 778G+ 5G | Adreno 642L | ✅ | ✅ |
| **Xiaomi Mi 8 SE**<br>*(none)* | `xmsirius` | [crDroid 12.11 (Unofficial)](https://github.com/Rocky7842/OTA_provider/releases/download/xmsirius-crDroid-12.11-20260609/crDroidAndroid-16.0-20260609-xmsirius-v12.11.zip) | 4.9 | ? | Qualcomm Snapdragon 710 | Adreno 616 | ? | ? |
| **Xiaomi Mi 6**<br>*(none)* | `sagit` | [LinageOS 22.2](https://mirrorbits.lineageos.org/full/sagit/20260703/lineage-22.2-20260703-nightly-sagit-signed.zip) | 4.4 | Magisk | Qualcomm Snapdragon 835 | Adreno 540 | ? | ? |
| **Xiaomi Redmi Note 9 Pro**<br>*(none)* | `joyeuse` | [crDroid 11.7](https://sourceforge.net/projects/crdroid/files/miatoll/11.x/crDroidAndroid-15.0-20250723-miatoll-v11.7.zip/download) | 4.14 | Magisk | Qualcomm Snapdragon 720G | Adreno 618 | ✅ | ? |

Why Xiaomi Mi 8 SE and Xiaomi Mi 6 have ? at Screen and Touch?  
Because we have internet problems in the chroot and can not install xfce right now, we will fix it 
