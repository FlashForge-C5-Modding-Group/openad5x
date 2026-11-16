# Project layout

OpenAD5X is split over a few repositories in the [FlashForge-C5-Modding-Group](https://github.com/FlashForge-C5-Modding-Group) organisation. The AD5X ones mirror the Creator 5 project's:

| Creator 5 | AD5X | What it holds |
|---|---|---|
| `OpenCreator` | `openad5x` (this repository) | The documentation site |
| `opencreator-fs` | `AD5X-FS` | The files that go on the printer: configs, boot, MCU firmware images |
| `klipper-c5` / `kalico` | `kalico-ad5x` | Kalico with the AD5X MCU support, the IFS and the AFC modules it uses |
| `touchscreen-installer` | `touchscreen-installer` (branch `ad5x`) | The installer run from the printer's touchscreen |
| `grumpyscreen` | `grumpyscreen` | GrumpyScreen, the same release as the Creator 5 |
| `creator-5-update-creator` | `ad5x-update-creator` | Builds the update package (no longer used; the installer flashes the repo images) |

## What `AD5X-FS` holds

- `fs/usr/data/config/`: `printer.base.cfg`, `printer.cfg`, `moonraker.conf`, `macros.cfg` (homing, print start and end, stock AD5X pause and resume, load cell and probe, touchscreen buttons, pause at layer), and `AFC/` with `AFC.cfg`, `AFC_Hardware-IFS.cfg`, `AFC_Macro_Vars.cfg` and `ifs_macros.cfg`
- `fs/usr/data/openad5x/mcu-flash/`: `ad5x-mcu-flash` (flashes the mainboard and IFS live from a folder of `mcu-firmware/ad5x` images, and stages the eboard for the next power cycle), and `ifs_capture.py` and `ifs_catch.py`, which it uses to flash the IFS MCU over its serial port
- `fs/usr/data/openad5x/loadcell/loadcell.sh`: bed load cell commands used by `macros.cfg`
- `fs/usr/data/openad5x/grumpyscreen/grumpyscreen.cfg`: the GrumpyScreen config, with your own changes in `grumpyscreen.ini` in the config folder
- `mcu-firmware/ad5x/`: the AD5X MCU firmware images, with the Kalico build configs for the eboard, mainboard and IFS in `config/`
- `fs/usr/data/openad5x/firmware/firmwareExe`, `startup/` and `version.txt`: the boot. `firmwareExe` brings the network up and runs `startup/startup.sh`, which starts the scripts in `startup/scripts/`. See [Startup](architecture/startup.md)
- `fs/usr/data/openad5x/nginx/nginx.conf`: the nginx config (Fluidd and the Moonraker proxy)
- `fs/usr/data/openad5x/startup/commands/`: the commands GrumpyScreen runs (restart Klipper, the screen or Wi-Fi, support zip)
