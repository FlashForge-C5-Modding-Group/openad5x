# Files on the printer

The stock baseline is FlashForge AD5X firmware (software 3.1.0, control 1.1.1, kernel 2.0.1, library 2.0.1). Everything below is added or changed on top of it. Console access is by SSH as `root`.

The layout follows the installer in the `touchscreen-installer` repository (branch `ad5x`) and the files in `AD5X-FS`. It has not been installed on a printer yet. The test printer still has the [previous layout](#previous-layout-test-printer).

## Boot

| Path | What it is |
|---|---|
| `/usr/prog/PROGRAM/software/firmwareExe` | Replaced by the `firmwareExe` script. The stock binary is kept as `/usr/data/openad5x/firmwareExe.stock` |
| `/usr/data/openad5x/firmware/firmwareExe` | The source of that script |
| `/usr/data/openad5x/startup/startup.sh` | Starts every script in `startup/scripts/` |
| `/usr/data/openad5x/startup/scripts/` | The boot scripts, see [Startup](startup.md) |
| `/usr/data/openad5x/klippy_restart.sh` | Stops Klippy; `10-klipper.sh` starts it again |

## Kalico and AFC

| Path | What it is |
|---|---|
| `/usr/data/openad5x/klipper/klipper` | The `kalico-ad5x` checkout |
| `/usr/data/openad5x/klipper/klippy-env` | Python virtual environment on `python-hf`, with system site packages |
| `/usr/data/openad5x/klipper/config` | The printer config, from `AD5X-FS` (`fs/usr/data/config`) |
| `/usr/data/openad5x/klipper/logs/printer.log` | Kalico log |
| `/usr/data/AFC-Klipper-Add-On` | The AFC add-on at commit `5ea84ea`, without `.git`. Its modules, and `AFC_IFS.py` and `ad5x_filament_sensor.py` from `/usr/data/openad5x/afc-ifs`, are linked into `klippy/extras` at every start |
| `/usr/data/openad5x/loadcell/loadcell.sh` | Bed load cell board on `ttyS7` (`H1`, `H7`), used by the `LOAD_CELL_TARE`, `LOAD_CELL_READ` and `LOAD_CELL_DIAGNOSTIC` macros |
| `/usr/data/openad5x/mcu-flash` | `ad5x-mcu-flash` and the IFS flash tools |
| `/usr/data/kalico-fw` | Staging for MCU firmware images, and `eboard.flash` |

## Web and touchscreen

| Path | What it is |
|---|---|
| `/usr/prog/moonraker/moonraker` | Moonraker (Arksine), cloned by the installer |
| `/usr/prog/moonraker/moonraker-env` | Its Python environment, on `python-hf` |
| `/opt/sbin/nginx` | nginx from Entware (`nginx-ssl`) |
| `/usr/data/openad5x/nginx/nginx.conf` | nginx config: Fluidd on port 80, API and `/websocket` to Moonraker, `/webcam/` to the camera |
| `/usr/data/fluidd` | Fluidd, from the latest release |
| `/usr/data/grumpyscreen` | GrumpyScreen (grumpy-ff release) |
| `/usr/prog/mjpg-streamer` | FlashForge's mjpg-streamer, unchanged |

## Toolchain

| Path | What it is |
|---|---|
| `/usr/data/bin/opt` | Entware, bind-mounted on `/opt`, with gcc, git, git-http, ca-bundle and nginx-ssl |
| `/usr/data/python-hf` | Python 3.13.9 hard-float |

See [Entware and Python](entware-python.md).

## MCU firmware

Both the mainboard and the eboard on the test printer run `kalico-ad5x` v2026.10.00-160-ge5e1da62, flashed on 2026-10-23. The mainboard was flashed with `NationsCommand`, and the eboard with `IAPCommand` through the startup hook. The stock images are the way back: `/usr/prog/PROGRAM/control/1.1.1/AD5X.bin` for the mainboard, `ADM_App.hex` for the eboard. `IAPCommand` deletes `/usr/prog/PROGRAM/control/Update` and `NationsCommand` deletes `UpdateM`.

The installer flashes the images in `mcu-firmware/ad5x` with `ad5x-mcu-flash`; see [Flashing](../mcu/flashing.md).

FlashForge's own Klipper no longer runs with these MCUs (MCU protocol error, `config_lis2dw`) until the host runs Kalico.

## Previous layout (test printer)

The test printer still has the layout it was tested with:

| Path | What it is |
|---|---|
| `/usr/prog/app_startup.sh` | The `firmwareExe` start and restart block replaced by a call to `startup.sh` |
| `/usr/prog/openad5x/startup.sh`, `/usr/data/openad5x/startup.d/` | The startup core and its drop-ins |
| `/usr/data/kalico/{klipper,klippy-env,start.sh}` | Kalico, its environment and the loop that keeps Klippy running |
| `/usr/data/config/kalico/` | The Kalico config, a copy of the stock `printer.cfg` and `printer.base.cfg` with `max_accel_to_decel` replaced by `minimum_cruise_ratio: 0.75` |
| `/usr/data/logs/klippy.log` | Kalico log |
| `/usr/data/moonraker`, `/usr/data/moonraker-env` | Moonraker on FlashForge's Python 3.8 and its packages |
| `/usr/data/nginx` | nginx and `nginx.conf` |
| `/usr/data/ad5x-afc` | `AFC_IFS.py`, linked into `klippy/extras` |
