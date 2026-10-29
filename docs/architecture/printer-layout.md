# Files on the printer

The stock baseline is FlashForge AD5X firmware (software 3.1.0, control 1.1.1, kernel 2.0.1, library 2.0.1). Everything below is added or changed on top of it. Console access is by SSH as `root`.

## Startup

| Path | What it is |
|---|---|
| `/usr/prog/app_startup.sh` | The `firmwareExe` start and restart block is replaced by a call to `startup.sh` |
| `/usr/prog/openad5x/startup.sh` | The startup core |
| `/usr/data/openad5x/startup.d/` | The drop-in scripts |

## Web and touchscreen

| Path | What it is |
|---|---|
| `/usr/data/moonraker` | Moonraker (`moonraker-ad5x.tar.gz`) |
| `/usr/data/moonraker-env` | Moonraker's Python packages and libraries |
| `/usr/data/config/moonraker.conf` | Moonraker config |
| `/usr/data/nginx` | nginx and `nginx.conf` (`fluidd-ad5x.tar.gz`) |
| `/usr/data/fluidd` | Fluidd v1.37.6 |
| `/usr/data/tmp` | nginx temp files |
| `/usr/data/grumpyscreen` | GrumpyScreen (grumpy-ff release) |
| `/usr/prog/mjpg-streamer` | FlashForge's mjpg-streamer, unchanged |

## Kalico

| Path | What it is |
|---|---|
| `/usr/data/kalico/klipper` | The `kalico-ad5x` checkout |
| `/usr/data/kalico/klippy-env` | Python virtual environment on `python-hf`, with system site packages |
| `/usr/data/kalico/start.sh` | Keeps Klippy running |
| `/usr/data/kalico/loadcell.sh` | Bed load cell board on `ttyS7` (`H1`, `H7`), used by the `LOAD_CELL_TARE`, `LOAD_CELL_READ` and `LOAD_CELL_DIAGNOSTIC` macros |
| `/usr/data/config/kalico/` | Kalico config: a copy of the stock `printer.cfg` and `printer.base.cfg`, with `max_accel_to_decel` replaced by `minimum_cruise_ratio: 0.75` |
| `/usr/data/logs/klippy.log` | Kalico log |
| `/usr/data/kalico-fw` | Kalico MCU firmware images |

## Toolchain

| Path | What it is |
|---|---|
| `/usr/data/bin/opt` | Entware, bind-mounted on `/opt`, with gcc, git, git-http and ca-bundle |
| `/usr/data/python-hf` | Python 3.13.9 hard-float |

See [Entware and Python](entware-python.md).

## MCU firmware

Both the mainboard and the eboard run `kalico-ad5x` v2026.10.00-160-ge5e1da62, flashed on 2026-10-23. The mainboard was flashed with `NationsCommand`, and the eboard with `IAPCommand` through the startup hook. The stock images are the way back: `/usr/prog/PROGRAM/control/1.1.1/AD5X.bin` for the mainboard, `ADM_App.hex` for the eboard. `IAPCommand` deletes `/usr/prog/PROGRAM/control/Update` and `NationsCommand` deletes `/usr/prog/PROGRAM/control/1.1.1/UpdateM`. See [Flashing](../mcu/flashing.md).

FlashForge's own Klipper no longer runs with these MCUs (MCU protocol error, `config_lis2dw`) until the host runs Kalico.
