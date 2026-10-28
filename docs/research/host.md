# Kalico host on the AD5X: what was done (for the installer)

Order as run on the printer, 2026-10-23. Each step with its result. Plan: `host-plan.md`.

## 0. Before (already in place)

- Python 3.13.9 hard-float in `/usr/data/python-hf` (opencreator-fs `python-3.13-hardfloat-r2`), see `openad5x/readme.plan` "Python 3.13"
- Entware in `/usr/data/bin/opt` on `/opt`, gcc + headers, **empty `specs` file renamed** (`/opt/lib/gcc/mipsel-openwrt-linux-gnu/8.4.0/specs` -> `specs.empty`), see `openad5x/readme.plan` "Entware"
- `startup.d/05-entware.sh` (legacy NaN byte `0x00a130d1` for kernel package 2.0.1, bind mount, `rc.unslung start`)
- Mainboard + eboard flashed with kalico-ad5x `e5e1da62`, see `../mcu-development.md`

## 1. git from Entware

```sh
export PATH=/opt/bin:/opt/sbin:$PATH
opkg update
opkg install git git-http ca-bundle
```
- git 2.50.1; `/usr/data` 1.6 GB free after

## 2. Kalico checkout

```sh
mkdir -p /usr/data/kalico
git clone --depth 1 https://github.com/FlashForge-C5-Modding-Group/kalico-ad5x.git /usr/data/kalico/klipper
git -C /usr/data/kalico/klipper rev-parse --short HEAD    # e5e1da6
```
- 260.7 MB (most of it `lib/`, the MCU vendor SDKs)
- The checkout must be the same commit the MCU firmware was built from

## 3. venv + c_helper.so

```sh
/usr/data/python-hf/bin/python3.13 -m venv --without-pip --system-site-packages /usr/data/kalico/klippy-env
cd /usr/data/kalico/klipper/klippy
PATH=/usr/data/python-hf/cc/bin:/opt/bin:$PATH /usr/data/kalico/klippy-env/bin/python -c 'import chelper; chelper.get_ffi()'
```
- `pyvenv.cfg`: `home = /usr/data/python-hf/bin`, `include-system-site-packages = true`, `version = 3.13.9`
- `klippy/chelper/c_helper.so` 305892 B, flags `0x70001407` nan2008 mips32r2
- klippy rebuilds it on start when chelper sources are newer (after a Kalico update): needs the same PATH (python-hf `cc/bin` + `/opt/bin`) and `/opt` mounted

## 4. Config: stock copied as it is

```sh
mkdir -p /usr/data/config/kalico
cp /usr/data/config/printer.cfg /usr/data/config/printer.base.cfg /usr/data/config/kalico/
```
- `printer.cfg` 2283 B, `printer.base.cfg` 5245 B (the printer's own, with its calibration: bed mesh, PID, input shaper)
- Stock `/usr/data/config/printer.cfg` and `printer.base.cfg` left untouched (stock Klipper still uses them)

## 5. First start (by hand, until reboot)

```sh
/usr/prog/klipper/klipperDaemon stop
PATH=/usr/data/python-hf/cc/bin:$PATH:/opt/bin nohup /usr/data/kalico/klippy-env/bin/python \
  /usr/data/kalico/klipper/klippy/klippy.py /usr/data/config/kalico/printer.cfg \
  -l /usr/data/logs/klippy.log -a /tmp/uds > /usr/data/logs/klippy.out 2>&1 &
```
- Moonraker connects by itself (`klippy_uds_address: /tmp/uds`, no change to moonraker.conf)

## 6. Config errors Kalico reported, and the fixes

| # | Error | File / line | Fix |
|---|---|---|---|
| 1 | `Option 'max_accel_to_decel' is not valid in section 'printer'` | `kalico/printer.base.cfg:137` `max_accel_to_decel:5000` | `minimum_cruise_ratio: 0.75` (20000 * (1 - 0.75) = 5000, same as stock) |

Fix as run: `sed -i '137s/^max_accel_to_decel:5000$/minimum_cruise_ratio: 0.75/' /usr/data/config/kalico/printer.base.cfg`, then Moonraker `POST /printer/restart`.

## 6b. Load cell (bed) commands

- `/usr/data/kalico/loadcell.sh` + `/usr/data/config/kalico/loadcell.cfg` + `[include loadcell.cfg]` in `kalico/printer.cfg`: Kalico's `LOAD_CELL_TARE` / `LOAD_CELL_READ` / `LOAD_CELL_DIAGNOSTIC` names as macros, sent to the bed board on ttyS7 as `H1` / `H7`. Details and sources: `../loadcell/NOTES.md`
- Test entry `[output_pin level_res] pin: PC0` also in `kalico/printer.cfg` (stock drives PC0 high at boot; not needed for the load cell)

## 7. Result

- klippy `ready`, no other config errors or warnings in `klippy.log`
- Moonraker `/printer/info`: `software_version` `e5e1da6`, `python_path` `/usr/data/kalico/klippy-env/bin/python`
- `Loaded MCU 'mcu' 137 commands (Kalico v2026.10.00-160-ge5e1da62-dirty-20261023_055547-bob ...)`, `Configured MCU 'mcu' (1024 moves)`, measured 144000698 Hz
- `Loaded MCU 'eboard' 137 commands (Kalico v2026.10.00-160-ge5e1da62-dirty-20261023_062032-bob ...)`, `Configured MCU 'eboard' (1024 moves)`, measured 144000659 Hz
- stock's `config_lis2dw` protocol error gone
- MCU builds say `-dirty`: built from a CRLF->LF converted copy on the PC; same commit as the host

## Not done yet

- Boot: openad5x `startup.sh` still starts stock Klipper; after a reboot stock runs again (protocol error) until the `startup.sh` switch + `/usr/data/kalico/start.sh` (`PLAN.md` steps 6-7)
- Entware mount before Klipper at boot (`host-plan.md` step 7)
- Hardware checks: temperatures, heaters, lis2dw, probe accuracy, bed mesh (done 2026-10-23: TMC UART on X/Y/Z, homing X/Y/Z, probe PB3 triggers, see `../loadcell/NOTES.md`)
- FlashForge-only commands gone (`QUERY_ADC`, `GET_FILAMENT_VALUE`, `GET_CUT_VALUE`, `SDCARD_SET_CHANNEL` ...)
- IFS: still stock firmware, not in the config
