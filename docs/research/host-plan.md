# Kalico on the AD5X host: plan

Goal: klippy from `kalico-ad5x` on the printer, on Python 3.13 (`/usr/data/python-hf`), talking to the Kalico mainboard and eboard, with Moonraker / Fluidd / GrumpyScreen as now.
Stock FlashForge Klipper (`/usr/prog/klipper`) and its config stay untouched, so going back is one switch.

Reference: OpenCreator (C5) `touchscreen-installer` `payload-template/soc/install-stack.sh` and `opencreator-fs` `startup/scripts/10-klipper.sh` (same Python bundle, same Kalico-on-host idea).

## Already in place

| What | Where | State |
|---|---|---|
| Python 3.13.9 hard-float | `/usr/data/python-hf` | installed, packages import |
| Entware + gcc | `/usr/data/bin/opt` on `/opt` | installed, mounted at boot (`startup.d/05-entware.sh`), specs fix done |
| c_helper.so build | python-hf `cc/bin/gcc` wrapper + `/opt/bin/gcc` | tested with kalico-ad5x chelper (~46 s) |
| Mainboard firmware | ttyS2 | kalico-ad5x `e5e1da62` |
| Eboard firmware | ttyS5 | kalico-ad5x `e5e1da62` |
| kalico-ad5x patches 1-5 | GitHub `main` | committed and pushed, HEAD `e5e1da62` = flashed firmware |
| Moonraker | `/usr/data/moonraker`, `-d /usr/data` | config `/usr/data/config`, logs `/usr/data/logs`, gcodes `/usr/data/gcodes`, `klippy_uds_address: /tmp/uds` |

## Layout

| Path | What |
|---|---|
| `/usr/data/kalico/klipper` | kalico-ad5x checkout (git, shallow) |
| `/usr/data/kalico/klippy-env` | `python-hf -m venv --without-pip --system-site-packages` |
| `/usr/data/kalico/start.sh` | starts klippy in a loop (like OpenCreator `10-klipper.sh`) |
| `/usr/data/config/kalico/printer.cfg` (+ includes) | Kalico config, in Moonraker's config root so Fluidd can edit it |
| `/usr/data/logs/klippy.log` | Kalico log (stock keeps `printer.log`) |
| `/tmp/uds` | API socket, same as stock, so Moonraker needs no change |

Stock files left as they are: `/usr/prog/klipper/`, `/usr/data/config/printer.cfg`, `/usr/data/config/printer.base.cfg`.

## Steps

Each step only after an OK; nothing moves or heats.
Done 2026-10-23: 1-4 (config copied from stock as it is, not rewritten), 8 (by hand, ready after one fix). What was run and the results: `NOTES.md`. Done 2026-10-24: 6 (`host/start.sh`, output to `klippy.out`), 7 (openad5x `startup.sh` starts it with `setsid` when executable; `klippy_restart.sh` now kills stock and Kalico klippy and lets the loop restart it). 9 (power cycle: loop + one Kalico klippy, no stock, ready).

1. Entware: `opkg install git git-http ca-bundle` (git over https)
2. `git clone --depth 1 https://github.com/FlashForge-C5-Modding-Group/kalico-ad5x.git /usr/data/kalico/klipper`, check `git rev-parse HEAD` = `e5e1da62`
3. `/usr/data/python-hf/bin/python3.13 -m venv --without-pip --system-site-packages /usr/data/kalico/klippy-env`
4. Build c_helper: `cd /usr/data/kalico/klipper/klippy && PATH=/usr/data/python-hf/cc/bin:/opt/bin:$PATH /usr/data/kalico/klippy-env/bin/python -c 'import chelper; chelper.get_ffi()'`
5. Config: write `/usr/data/config/kalico/printer.cfg` from the stock files (below), copied to the printer, no other file changed
6. `/usr/data/kalico/start.sh`:
   ```sh
   #!/bin/sh
   # Kalico klippy on python-hf, restarts after exit
   export PATH=/usr/data/python-hf/cc/bin:$PATH:/opt/bin
   K=/usr/data/kalico
   while true; do
       $K/klippy-env/bin/python $K/klipper/klippy/klippy.py /usr/data/config/kalico/printer.cfg \
           -l /usr/data/logs/klippy.log -a /tmp/uds
       sleep 3
   done
   ```
7. openad5x `startup.sh`: start `/usr/data/kalico/start.sh` when it exists, else stock `/usr/prog/klipper/start.sh` (going back = `chmod -x /usr/data/kalico/start.sh` or rename, reboot). Entware must be mounted before klippy (gcc, only needed after a Kalico update): klippy is started before `startup.d`, so `05-entware.sh` either moves into the core before Klipper, or `start.sh` mounts `/opt` itself
8. First start by hand (stock Klipper stopped), check `klippy.log`, Moonraker `/printer/info` = ready, `mcu` / `mcu eboard` versions = host version
9. Then boot test (power cycle)

## Config from stock (`/usr/prog/config/printer.cfg` + `printer.base.cfg`)

All sections exist in Kalico (`bed_mesh display_status exclude_object extruder fan_generic force_move gcode_arcs gcode_macro heater_bed heater_fan idle_timeout input_shaper led lis2dw mcu pause_resume pid_calibrate printer probe resonance_tester stepper_x/y/z temperature_sensor tmc2209 verify_heater virtual_sdcard`).

Changes needed:
- `[printer]` `max_accel_to_decel: 5000`: not read by Kalico any more (`toolhead.py` derives it from `minimum_cruise_ratio`), remove; `minimum_cruise_ratio: 0.75` gives 20000 * 0.25 = 5000 (same as stock)
- `[virtual_sdcard] path: /usr/data/gcodes` (same as stock)
- FlashForge-only commands are not in the config itself (they come from FlashForge's `query_adc.py` / `virtual_sdcard.py`): `QUERY_ADC`, `GET_FILAMENT_VALUE`, `GET_CUT_VALUE`, `SDCARD_SET_CHANNEL` etc. won't exist; the `filamentValue` / `cutValue` sensors stay as `temperature_sensor` (Generic 3950 on eboard PA3 / PA2)
- Macros `M900 M106 M107 HOME MYG67` use standard commands only, keep
- Calibration to take over from the printer's `/usr/data/config/printer.cfg` (not the dump): `z_offset`, bed mesh, PID, input shaper (OpenCreator does this with `import-stock-calibration.sh`)
- IFS not in this config yet (stock IFS firmware; AFC later)

## Going back to stock

1. Host: stop Kalico, start stock (`/usr/prog/klipper/start.sh`), disable `/usr/data/kalico/start.sh`
2. Mainboard: `NationsCommand -c -d --fn /usr/prog/PROGRAM/control/1.1.1/AD5X.bin --v -r`
3. Eboard: `echo /usr/prog/PROGRAM/control/1.1.1/ADM_App.hex > /usr/data/kalico-fw/eboard.flash`, power cycle

## Open

- Where to put Kalico's `printer.cfg` (above: `/usr/data/config/kalico/`) vs replacing the stock `printer.cfg`
- Get Kalico via Entware git (above) or copy a checkout from the PC with pscp (no git on the printer)
- Moonraker update manager for Kalico (none now, `[update_manager]` left out on purpose)
