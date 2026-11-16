# Startup

How the printer boots with OpenAD5X. The structure follows [OpenCreator](opencreator.md): a `firmwareExe` script brings the network up and hands over to `startup.sh`, which starts a folder of scripts. The files are in `AD5X-FS` under `fs/usr/data/openad5x/`.

## The chain

1. FlashForge's `/usr/prog/app_startup.sh` runs the USB hook, the control update check and the drivers, then starts `/usr/prog/PROGRAM/software/firmwareExe -1 -D -qws`. After 10 s it copies the stock binary back and starts it again unless a process named `firmwareExe` is running.
2. The installer replaces that file with the `firmwareExe` script. The stock binary is kept as `/usr/data/openad5x/firmwareExe.stock`.
3. The script sets the legacy NaN byte, mounts Entware if needed, and brings the network up from `Adventurer5M.json`: hotspot, Wi-Fi or ethernet (with a cable watch), static addresses included. It then runs `startup/startup.sh` and stays alive in a sleep loop, so `app_startup.sh` does not restore the stock binary. The network comes first, so SSH still works if a later script breaks.
4. `startup.sh` starts every script in `/usr/data/openad5x/startup/scripts/` in the background, in name order.

## The scripts

| Script | What it does |
|---|---|
| `01-fixnan.sh` | Sets the legacy NaN byte for Entware's binaries (`0x00a130d1` on kernel package 2.0.1). Called by `firmwareExe` and `05-entfix.sh` |
| `02-fixtime.sh` | Sets the clock (see below) |
| `05-entfix.sh` | Bind-mounts Entware on `/opt` and runs `rc.unslung start` |
| `06-sftp.sh` | SFTP for dropbear (see [Network](network.md)) |
| `08-mcu-wake.sh` | Starts the eboard application, flashing it first when asked, then wakes the eboard again whenever Klippy cannot reach it |
| `10-klipper.sh` | Creates empty AFC variable files when missing, waits for the eboard, syncs the Klipper plugins (`oc-plugin sync`) and keeps Klippy running |
| `20-moonraker.sh` | Moonraker from `/usr/prog/moonraker`, data folder `/usr/data/openad5x/klipper` |
| `25-fluidd-macros.sh` | Once Moonraker is up, gives Fluidd the OpenAD5X macro groups (`fluidd/macros.json`) if it has no layout yet |
| `25-nginx.sh` | Entware's nginx, with Fluidd on port 80 |
| `30-camera.sh` | FlashForge's mjpg-streamer on port 8080 |
| `40-grumpyscreen.sh` | GrumpyScreen with `DISPLAY_ROTATE=0`, the full config `openad5x/grumpyscreen/grumpyscreen.cfg` and your changes in `config/grumpyscreen.ini`; at every boot it sets `hide_spoolman` (from `[spoolman]` in `moonraker.conf`) and `hide_mmu` (from AFC in `printer.cfg`) in the `.ini` |
| `99-opencreator-updater.sh` | Runs `opencreator_updater.py`, which merges AD5X-FS config updates into the live config and keeps the `openad5x` folders current (log `/tmp/openad5x-updater.log`) |

The scripts run in parallel, so a script that needs another one waits for it: `10-klipper.sh` for the eboard (`/tmp/openad5x-eboard-ready`, up to 90 s), and `25-nginx.sh` and `06-sftp.sh` for `/opt`.

## Eboard start and flash hook

`08-mcu-wake.sh` talks to the eboard bootloader on `ttyS5` at 115200 before Klippy connects. It waits for the `Ready` lines and sends `A`; the bootloader answers ACK (`0x06`) and starts the application. If `/usr/data/kalico-fw/eboard.flash` exists, it holds the path of a `.hex` to flash first with `IAPCommand`. The file is deleted once the flash log shows `STM32Write: success`; after a failure it stays and is tried again at the next power-on (once per boot). The log is `/usr/data/logs/openad5x/eboard-flash.log`. See [Flashing](../mcu/flashing.md).

## Clock

The printer has no battery clock and boots at 1970. `02-fixtime.sh` sets it from the network with `rdate` once `time.nist.gov` answers a ping, trying up to 30 times 2 seconds apart.

The clock matters because with a 1970 date HTTPS fails with "certificate is not yet valid".

## Web access

Fluidd is at `http://<printer>/` through nginx, and Moonraker is on port 7125.

## Logs

| Log | Contents |
|---|---|
| `/tmp/openad5x.log` | `firmwareExe`, `startup.sh` and the scripts' launcher messages |
| `/tmp/<script>.log` | Output of each script |
| `/usr/data/openad5x/klipper/logs/printer.log` | Klippy |
| `/usr/data/logs/mcu-wake.log`, `/usr/data/logs/openad5x/eboard-flash.log` | Eboard wake and flash |
| `/usr/data/logs/mcu-flash.log` | `ad5x-mcu-flash` |
| `/usr/data/logs/nginx-error.log` | nginx |

## Recovery

If the scripts break, the network and SSH are still up. To go back to the stock firmware, copy `/usr/data/openad5x/firmwareExe.stock` over `/usr/prog/PROGRAM/software/firmwareExe`. Keep a copy of the original `app_startup.sh` (the official file, md5 `08ba2971...`) off the printer.

## Previous boot

Before this, the test printer used one line in `app_startup.sh`, replacing the `firmwareExe` block:

```sh
/usr/prog/openad5x/startup.sh > /usr/data/logs/openad5x.log 2>&1 &
```

That `startup.sh` ran the eboard, Klipper (`/usr/data/kalico/start.sh`), the network and the clock in a fixed order, then the drop-ins in `/usr/data/openad5x/startup.d/` one after another. It is what the power-cycle tests below ran on. Its clock was `/usr/prog/ntpclient -c 1 -s -h pool.ntp.org` every 5 s until the year was 2024 or later (`-c 1` sets the time once and exits; without it `ntpclient` stays running and re-syncs every 600 s).

## Tested

On the previous boot, power-cycle tests passed on 2026-10-10 (eboard, Klipper with both MCUs configured, network, Moonraker, nginx), on 2026-10-11 (the clock: set, no `ntpclient` left running, no certificate errors) and on 2026-10-23 (Entware and gcc).
