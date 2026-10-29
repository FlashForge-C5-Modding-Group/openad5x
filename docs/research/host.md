# Kalico on the AD5X host

How Klippy from `kalico-ad5x` is installed on the printer: on Python 3.13 (`/usr/data/python-hf`), talking to the Kalico mainboard and eboard, with Moonraker, Fluidd and GrumpyScreen as before.

FlashForge's own Klipper (`/usr/prog/klipper`) and its config stay untouched, so going back is one switch. The approach follows OpenCreator's `touchscreen-installer` (`payload-template/soc/install-stack.sh`) and `opencreator-fs` (`startup/scripts/10-klipper.sh`): the same Python bundle and the same Kalico-on-host idea.

## What has to be in place first

| What | Where |
|---|---|
| Python 3.13.9 hard-float | `/usr/data/python-hf` |
| Entware with gcc, and the empty `specs` file renamed | `/usr/data/bin/opt`, mounted on `/opt` at boot by `startup.d/05-entware.sh` |
| The `c_helper.so` build | the `python-hf` `cc/bin/gcc` wrapper and `/opt/bin/gcc` |
| Mainboard and eboard firmware built from the same `kalico-ad5x` commit as the host checkout | `ttyS2` and `ttyS5` |
| Moonraker | `/usr/data/moonraker`, started with `-d /usr/data`: config in `/usr/data/config`, logs in `/usr/data/logs`, gcodes in `/usr/data/gcodes`, `klippy_uds_address: /tmp/uds` |

See [Entware and Python](../architecture/entware-python.md) and [Flashing](../mcu/flashing.md).

## Layout

| Path | What |
|---|---|
| `/usr/data/kalico/klipper` | The `kalico-ad5x` checkout (git, shallow) |
| `/usr/data/kalico/klippy-env` | `python-hf -m venv --without-pip --system-site-packages` |
| `/usr/data/kalico/start.sh` | Starts Klippy in a loop (like OpenCreator's `10-klipper.sh`) |
| `/usr/data/config/kalico/printer.cfg` and its includes | The Kalico config, in Moonraker's config root so Fluidd can edit it |
| `/usr/data/logs/klippy.log` | The Kalico log (stock keeps `printer.log`) |
| `/tmp/uds` | The API socket, the same as stock, so Moonraker needs no change |

These stock files are left as they are: `/usr/prog/klipper/`, `/usr/data/config/printer.cfg` and `/usr/data/config/printer.base.cfg`.

## Installing

### 1. Git from Entware

```sh
export PATH=/opt/bin:/opt/sbin:$PATH
opkg update
opkg install git git-http ca-bundle
```

This installs git 2.50.1 and leaves 1.6 GB free on `/usr/data`.

### 2. The Kalico checkout

```sh
mkdir -p /usr/data/kalico
git clone --depth 1 https://github.com/FlashForge-C5-Modding-Group/kalico-ad5x.git /usr/data/kalico/klipper
git -C /usr/data/kalico/klipper rev-parse --short HEAD
```

The checkout is about 260 MB, most of it `lib/` (the MCU vendor SDKs). It must be the same commit the MCU firmware was built from.

### 3. The virtual environment and `c_helper.so`

```sh
/usr/data/python-hf/bin/python3.13 -m venv --without-pip --system-site-packages /usr/data/kalico/klippy-env
cd /usr/data/kalico/klipper/klippy
PATH=/usr/data/python-hf/cc/bin:/opt/bin:$PATH /usr/data/kalico/klippy-env/bin/python -c 'import chelper; chelper.get_ffi()'
```

`pyvenv.cfg` ends up with `home = /usr/data/python-hf/bin`, `include-system-site-packages = true` and `version = 3.13.9`. `klippy/chelper/c_helper.so` is about 305 KB, flags `0x70001407` (nan2008, mips32r2).

Klippy rebuilds `c_helper.so` on start when the `chelper` sources are newer, for example after a Kalico update. That needs the same `PATH` (`python-hf` `cc/bin` and `/opt/bin`) and `/opt` mounted.

### 4. The config: stock, copied

```sh
mkdir -p /usr/data/config/kalico
cp /usr/data/config/printer.cfg /usr/data/config/printer.base.cfg /usr/data/config/kalico/
```

This takes the printer's own files, with its calibration (bed mesh, PID, input shaper). Stock keeps using the originals.

### 5. The start script

`/usr/data/kalico/start.sh`:

```sh
#!/bin/sh
# Kalico klippy on python-hf, restarts after exit
export PATH=/usr/data/python-hf/cc/bin:$PATH:/opt/bin
K=/usr/data/kalico
cd /
while true; do
    $K/klippy-env/bin/python $K/klipper/klippy/klippy.py /usr/data/config/kalico/printer.cfg \
        -l /usr/data/logs/klippy.log -a /tmp/uds >> /usr/data/logs/klippy.out 2>&1 < /dev/null
    sleep 3
done
```

`startup.sh` starts it with `setsid` when it is executable, and otherwise starts the stock Klipper. Entware must be mounted before Klippy needs a compiler, which is only after a Kalico update. `klippy_restart.sh` stops every Klippy (stock and Kalico) and lets the loop start one again.

### 6. Starting by hand

To try it without rebooting, stop stock Klipper and start Klippy yourself:

```sh
/usr/prog/klipper/klipperDaemon stop
PATH=/usr/data/python-hf/cc/bin:$PATH:/opt/bin nohup /usr/data/kalico/klippy-env/bin/python \
  /usr/data/kalico/klipper/klippy/klippy.py /usr/data/config/kalico/printer.cfg \
  -l /usr/data/logs/klippy.log -a /tmp/uds > /usr/data/logs/klippy.out 2>&1 &
```

Moonraker connects by itself, because `klippy_uds_address` is already `/tmp/uds`.

## Config changes from stock

All the stock sections exist in Kalico (`bed_mesh display_status exclude_object extruder fan_generic force_move gcode_arcs gcode_macro heater_bed heater_fan idle_timeout input_shaper led lis2dw mcu pause_resume pid_calibrate printer probe resonance_tester stepper_x/y/z temperature_sensor tmc2209 verify_heater virtual_sdcard`). What changes:

| Stock | Change |
|---|---|
| `[printer] max_accel_to_decel: 5000` | Kalico reports `Option 'max_accel_to_decel' is not valid in section 'printer'`. Replace it with `minimum_cruise_ratio: 0.75` (20000 x (1 - 0.75) = 5000, the same as stock) |
| `[virtual_sdcard] path` | `/usr/data/gcodes`, the same as stock |
| FlashForge-only commands (`QUERY_ADC`, `GET_FILAMENT_VALUE`, `GET_CUT_VALUE`, `SDCARD_SET_CHANNEL`, ...) | They come from FlashForge's own klippy files, so they do not exist in Kalico. The `filamentValue` and `cutValue` sensors stay as `temperature_sensor` (Generic 3950 on eboard PA3 and PA2) |
| Macros `M900 M106 M107 HOME MYG67` | Use standard commands only, kept |
| Calibration | Taken over from the printer's own `/usr/data/config/printer.cfg`: `z_offset`, bed mesh, PID, input shaper |

The fix for the first error is `sed -i '137s/^max_accel_to_decel:5000$/minimum_cruise_ratio: 0.75/' /usr/data/config/kalico/printer.base.cfg`, then a Moonraker `POST /printer/restart`.

The load cell commands are added through `loadcell.cfg`, included from `printer.cfg`. See [Load cell in Kalico](loadcell-kalico.md). A test entry `[output_pin level_res] pin: PC0` (stock drives PC0 high at boot) is not needed for the load cell.

## What a good start looks like

- Klippy is `ready`, with no other config errors or warnings in `klippy.log`.
- Moonraker's `/printer/info` shows `software_version` as the checkout commit and `python_path` as `/usr/data/kalico/klippy-env/bin/python`.
- Each MCU logs `Loaded MCU '...' 137 commands (Kalico v2026.10.00-...)` and `Configured MCU '...' (1024 moves)`. The measured clocks were 144000698 Hz for the mainboard and 144000659 Hz for the eboard.
- Stock's `config_lis2dw` protocol error is gone.
- The MCU builds say `-dirty` when they were built from a CRLF-to-LF converted copy on a PC.

## Going back to stock

1. Host: stop Kalico, start stock with `/usr/prog/klipper/start.sh`, and disable `/usr/data/kalico/start.sh` (`chmod -x` or rename it, then reboot).
2. Mainboard: `NationsCommand -c -d --fn /usr/prog/PROGRAM/control/1.1.1/AD5X.bin --v -r`
3. Eboard: `echo /usr/prog/PROGRAM/control/1.1.1/ADM_App.hex > /usr/data/kalico-fw/eboard.flash`, then power-cycle.

## Open

- Where Kalico's `printer.cfg` should live: `/usr/data/config/kalico/` (now) or replacing the stock `printer.cfg`.
- Whether to get Kalico through Entware's git (now) or copy a checkout from a PC with `pscp`.
- A Moonraker update manager for Kalico. There is none on purpose: `[update_manager]` is left out of `moonraker.conf`.
