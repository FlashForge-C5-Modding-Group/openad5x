# Project layout

OpenAD5X is split over a few repositories in the [FlashForge-C5-Modding-Group](https://github.com/FlashForge-C5-Modding-Group) organisation. The AD5X ones mirror the Creator 5 project's:

| Creator 5 | AD5X | What it holds |
|---|---|---|
| `OpenCreator` | `openad5x` (this repository) | The documentation site |
| `opencreator-fs` | `AD5X-FS` | The files that go on the printer: configs, AFC and IFS modules, MCU firmware images |
| `klipper-c5` / `kalico` | `kalico-ad5x` | Kalico with the AD5X MCU support and the IFS |
| `touchscreen-installer` | `touchscreen-installer` (branch `ad5x`) | The installer run from the printer's touchscreen |
| `grumpyscreen` | `grumpy-ff` | Auto-build of GrumpyScreen for the FlashForge touchscreen |
| `creator-5-update-creator` | `ad5x-update-creator` | Builds the update package |

## What `AD5X-FS` holds

- `fs/usr/data/config/`: `printer.base.cfg`, `printer.cfg`, `ad5x_home.cfg`, `ad5x_print.cfg`, `loadcell.cfg`, `moonraker.conf`, and `AFC/` with `AFC.cfg`, `AFC_Hardware-IFS.cfg`, `AFC_Macro_Vars.cfg` and `ifs_macros.cfg`
- `fs/usr/data/openad5x/afc-ifs/`: `AFC_IFS.py` (the IFS unit for AFC) and `ad5x_filament_sensor.py`
- `fs/usr/data/openad5x/mcu-flash/`: `ad5x-mcu-flash` (flashes the mainboard and IFS live from a folder of `mcu-firmware/ad5x` images, and stages the eboard for the next power cycle), and `ifs_capture.py`, `ifs_catch.py`, `ifs_flash.sh` and `ifs_probe.py`, which flash the IFS MCU over its serial port
- `fs/usr/data/openad5x/loadcell/loadcell.sh`: bed load cell commands used by `loadcell.cfg`
- `mcu-firmware/ad5x/`: the AD5X MCU firmware images, with the Kalico build configs for the eboard, mainboard and IFS in `config/`
- `fs/usr/data/openad5x/firmware/firmwareExe`, `startup/` and `version.txt`: the boot. `firmwareExe` brings the network up and runs `startup/startup.sh`, which starts the scripts in `startup/scripts/`. See [Startup](architecture/startup.md)
- `fs/usr/data/openad5x/nginx/nginx.conf` and `klippy_restart.sh`: the nginx config (Fluidd and the Moonraker proxy) and the script that restarts Klippy
- `build/`: scripts that build the Fluidd and Moonraker packages of the previous layout (see [Packages](architecture/packages.md))
