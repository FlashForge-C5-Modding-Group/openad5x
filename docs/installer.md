# AD5X installer

The AD5X installs through the OpenCreator installer (`touchscreen-installer`, branch `ad5x`), as per-machine branches in the shared scripts ("if C5 then ..., if AD5X then ..."), not as separate AD5X copies. Every AD5X-only step is guarded by `OC_MACHINE=AD5X`, and the C5 paths are unchanged.

!!! note "Status"
    The steps below are written and their pieces were tested on a PC (checksums, the AFC download, the demo mode). A full install has not been run on a printer. The USB launcher at the end was tested on a real AD5X.

## Repos

| Repo | AD5X work |
|---|---|
| `touchscreen-installer` (branch `ad5x`) | Model detection (`AD5X`, PID `0026`), the AD5X boot hook (`flashforge_init.sh`), and the per-machine install steps below |
| `AD5X-FS` | What the installer copies onto the printer: `fs/usr/data/config/`, `fs/usr/data/openad5x/` (boot, AFC and IFS modules, nginx config, flash tools) and `mcu-firmware/ad5x/`. The installer clones it and keeps the clone as `/usr/data/openad5x/opencreator-fs` |
| `kalico-ad5x` | Kalico with the AD5X MCU support and the half-duplex RS485 IFS; commit `8ee87b51` |

## Where files go

`OC_HOME` is `/usr/data/openad5x` on the AD5X and `/usr/data/opencreator` on the C5. It is set in `payload-template/common/install-helpers.sh`, and in `scripts/install.sh` (which needs it before it knows the machine, so it reads `MACHINE=` from the stock `app_startup.sh`).

## The steps (SoC mode)

| Step | What it does on the AD5X |
|---|---|
| `01-install-entware` | Entware on `/usr/data/bin/opt`, mounted on `/opt`. No NaN switch address is passed |
| `02-install-loopscript` | Clones `AD5X-FS` and copies `startup`, `firmware`, `mcu-flash`, `loadcell`, `afc-ifs` and `nginx` from it into `/usr/data/openad5x`, keeping files you added |
| `05-install-python` | The hard-float Python 3.13 in `/usr/data/python-hf` |
| `10-install-stack` | Kalico (`kalico-ad5x`) into `/usr/data/openad5x/klipper/klipper`, a `klippy-env`, and the default `AD5X-FS` config into `…/klipper/config` |
| `12-install-afc` | The AFC add-on at commit `5ea84ea` into `/usr/data/AFC-Klipper-Add-On`, and AFC's `macros/` and an empty `mcu/` beside `AFC.cfg`. Skipped on the C5 |
| `15-install-moonraker` | Arksine's Moonraker into `/usr/prog/moonraker`, with an environment on `python-hf` |
| `17-install-timelapse` | Moonraker timelapse |
| `20-install-web` | Fluidd (or Mainsail) into `/usr/data/fluidd`, and Entware's `nginx-ssl` with the config in `/usr/data/openad5x/nginx/nginx.conf` (the AD5X has no nginx). Adds a Moonraker update entry for `AD5X-FS` |
| `30-install-grumpyscreen` | The `grumpy-ff` build of GrumpyScreen, when the touchscreen is chosen |
| `85-enable-root`, `86-enable-sftp` | Root login and SFTP (the `06-sftp.sh` boot script patches dropbear) |
| `90-activate-loopscript` | Replaces `firmwareExe` with the `firmwareExe` script, keeping the stock binary as `firmwareExe.stock` |
| `95-flash-mcu-firmware` | Flashes `mcu-firmware/ad5x` with `ad5x-mcu-flash`; see [Flashing](mcu/flashing.md) |

The boot these steps install is described in [Startup](architecture/startup.md).

## MCU firmware

The earlier plan built a stock-format update package (`ad5x-update-creator`) and let FlashForge's own updater flash it after two power cycles. That path was dropped. The stock `app_startup.sh` (3.1.5 and 3.1.6, read here) only reads `AD5X-*.tgz` from a mounted USB stick, and nothing else found picks up a package staged in `/usr/data`. The installer flashes the repo images directly instead, as the C5 installer does.

## Still open

- A full install run on real AD5X hardware (the screen and checks passed on 2026-10-25; Install itself has never been pressed)
- Moving the test printer from the previous boot to this one
- `opkg install nginx-ssl` and Entware's paths for nginx, Moonraker building on `python-hf`, `ifsF37` on the stock IFS, and `rdate` for the clock: none of these has run on a printer
- Merging config changes after an update from Moonraker's update manager (the C5 has `99-opencreator-updater` for this)
- Whether the printer's AFC macros differ from upstream `5ea84ea`
- Installer UI (`src/`) review for machine naming

## USB launcher: AD5X hardware bring-up findings (2026-10-25)

The stick was tested on the real AD5X (12 boots). Every fix lives in
touchscreen-installer `scripts/runFirmwareExe.sh` (shipped on the stick as
both runFirmwareExe.sh and flashforge_init.sh, the AD5X's hook name):

- AD5X hook: stock app_startup.sh runs /mnt/flashforge_init.sh (not the C5's
  runFirmwareExe.sh) and always continues the boot after it returns
- ethernet: openad5x-style config from Adventurer5M.json; udhcpc must run in
  the foreground (-n -q -t 5), backgrounded it silently never configured
- kill dhcpcd first: init starts one that keeps rewriting resolv.conf empty
  (stock kills it in app_startup.sh only after the hook)
- real MAC before DHCP: the driver boots with a random MAC and stock sets the
  real one (/usr/prog/MAC) only later; the interface must be downed to set it
- public DNS fallbacks appended to resolv.conf after DHCP
- touch mapping: the installer app has no calibration and trusts the driver's
  pixels, so the tsc2007 insmod carries the raw-to-pixel actrue window
  (X 309-3765, Y 705-3447, derived from FlashForge's shipped pointercal);
  stock's 0-4096 window compresses touch toward the centre
- rdate/"clock not set" was a DNS casualty, not port 37
- space gate: /usr/data is 5.5 GB; stock has ~5 GB free and passes the 2 GB
  check easily (this printer's 1.3 GB free is 3 GB of gcodes)
