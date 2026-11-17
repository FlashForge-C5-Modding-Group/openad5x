# Installation and safety

OpenAD5X is in public alpha.

!!! warning "Alpha"
    This is an alpha. Expect bugs, keep a backup, and know how to go back to stock.
    Report problems on the [Discord](https://discord.gg/RsdkqDtfww).

OpenAD5X is installed with the OpenCreator Installer, a touchscreen app that runs from a USB
drive and can back up the printer before changing anything. How it works inside is in
[Installer internals](installer.md).

## Supported FlashForge firmware

The installer accepts AD5X printers with FlashForge's kernel package **2.0.1**. On any other
kernel package it stops without changing anything.

## Requirements for USB

- [x] FAT32 partition
- [x] Room for the backup, if you choose one

## Requirements for printer

- [x] At least 256 MB free on `/usr/data` (the installer warns below that)
- [x] An active internet connection: the installer downloads Kalico, the AD5X files and the
      web UI during the install

## Steps to install OpenAD5X

1. Copy the installer files to the root of the USB drive. There is no published release yet:
   the files are built from the `touchscreen-installer` repository, branch `ad5x`, with `make usb`
   (they end up in `dist/usb`).
2. Reboot the printer with the USB drive plugged in.
3. Go through the steps on the touchscreen. SoC installs are recommended for people who don't
   know what tunnelled is. Pick Fluidd (recommended) or Mainsail, and whether to install
   GrumpyScreen.
4. Wait for the install to finish. It ends by flashing the printer's mainboard, toolhead board
   and IFS with Kalico.
5. When it's finished, remove the USB drive and reboot.
6. After the reboot you should see the OpenAD5X boot logo, GrumpyScreen on the touchscreen, and
   Fluidd in a browser at the printer's IP address.
7. Set up your slicer: follow [Slicer configuration](slicer-config.md) before your first print.
8. Run `ADX_QUICK_START` once (Calibration group in Fluidd's macros): input shaper, nozzle PID
   and bed PID, then it saves and restarts Klipper.

## Steps to update OpenAD5X

There are two ways.

### Way 1: Fluidd/Mainsail

1. Open the software update section.
2. Update **openad5x**, then **klipper**.
3. Restart Klipper, or reboot.

Your edits to the config files are kept: the updater merges the new templates into your files.
If your edit and the update change the same lines, it leaves a `.conflict` file next to yours to
sort out by hand.

### Way 2: OpenCreator Installer

For bigger updates, copy the new installer files over the old ones on the USB drive, plug it in
and reboot, then follow the steps on the touchscreen.

## Uninstalling OpenAD5X

Boot the installer from the USB drive. It offers:

- **Rollback to stock**: puts FlashForge's `firmwareExe` back, so the printer boots FlashForge's
  software again. OpenAD5X's files stay on the printer for a reinstall.
- **Restore backup**: restores the newest backup the installer made.

!!! warning "Files left over"
    After a rollback these stay on the printer and can be removed by hand:
    `/usr/data/openad5x`, `/usr/data/grumpyscreen` and `/usr/data/python-hf`.
    The OpenAD5X boot logo also stays until you restore a backup.

!!! danger "MCU firmware"
    The install flashes Kalico onto the mainboard, toolhead board and IFS. A rollback puts
    FlashForge's software back but not FlashForge's MCU firmware.
