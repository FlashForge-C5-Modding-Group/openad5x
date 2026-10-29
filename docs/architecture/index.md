# Architecture

OpenAD5X replaces FlashForge's closed programs on the AD5X with open-source ones. FlashForge's Linux stays as it is: there is no custom distribution.

The closed program being replaced is `firmwareExe` (`/usr/prog/PROGRAM/software/`). It is the screen app, but it also runs most of the printer.

The end goal is one OS for all FlashForge printers, so the layout follows OpenCreator (the Creator 5 project) wherever the printers allow. See [Differences from OpenCreator](opencreator.md).

## What `firmwareExe` does

Taken from `firmwareExe` 3.1.0.

### Must be replaced

The printer does not work without these.

| # | Job |
|---|---|
| 1 | Starts Klipper at boot (`/usr/prog/klipper/start.sh`) |
| 2 | Wakes the toolhead board at power-on (sends `A` on `/dev/ttyS5`) |
| 3 | Runs printing: start, pause, resume and cancel, through Klipper's API socket |
| 4 | Network: brings up `eth0` and Wi-Fi, saves Wi-Fi networks, hotspot mode |
| 5 | Power button and safe power-off |
| 6 | Touchscreen: all menus and screen sleep |

### Replace if used

| # | Job |
|---|---|
| 7 | IFS 4-colour unit (`/dev/ttyS4`): load, unload, colour change, cut, purge |
| 8 | Load cell weighing and crash detection (`/dev/ttyS7`) |
| 9 | Camera stream (`mjpg_streamer`, port 8080) |
| 10 | USB stick detection and printing |
| 11 | Buzzer sounds |
| 12 | Clock from the internet (`ntpclient`) |

### FlashForge-only, dropped

| # | Job |
|---|---|
| 13 | FlashForge cloud (MQTT, Alibaba OSS uploads) |
| 14 | FlashPrint and Orca network printing (Moonraker covers normal slicers) |
| 15 | FlashForge update system |
| 16 | FlashForge calibration and setup wizards |

## Progress

| Step | Status |
|---|---|
| Startup script that does jobs 1, 2 and 4 instead of `firmwareExe` | <span class="oc-status ok">Done</span> |
| Moonraker and the web UI; Kalico at boot (`/usr/data/kalico/start.sh`, stock Klipper if it is not executable) | <span class="oc-status ok">Done</span> |
| Open-source touchscreen app (GrumpyScreen, built by `grumpy-ff`) | <span class="oc-status ok">Done</span> |
| IFS and bed load cell | <span class="oc-status ok">Done</span>, see [IFS](../ifs/index.md) and [load cell](../research/loadcell.md) |
| Camera and clock | <span class="oc-status ok">Done</span> |
| Stop `firmwareExe` from starting | <span class="oc-status ok">Done</span> |
| Power button and power-off | Not needed, see [Power key](power.md) |
| USB stick, buzzer | As needed |

## In this section

| Page | What is in it |
|---|---|
| [Startup](startup.md) | The startup core, the drop-in scripts, logs and the clock |
| [Files on the printer](printer-layout.md) | What was added or changed on the printer, and where |
| [Network](network.md) | How stock handles Wi-Fi, Ethernet and the hotspot |
| [Touchscreen](touchscreen.md) | GrumpyScreen and the grumpy-ff build |
| [Camera](camera.md) | The mjpg-streamer set-up |
| [Power key](power.md) | Why the power key code is not needed |
| [Entware and Python](entware-python.md) | The compiler and Python 3.13 that Kalico needs on the printer |
| [Packages and builds](packages.md) | The Moonraker and Fluidd packages and how they are built |
| [Differences from OpenCreator](opencreator.md) | Where this project's layout differs from the Creator 5 one |
