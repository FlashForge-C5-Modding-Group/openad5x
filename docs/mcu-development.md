# AD5X mainboard + eboard notes

Goal: run Kalico on the host and on both MCUs, so the IFS can join as a Kalico MCU (see `ifs/index.md`).
A Klipper/Kalico host only talks to MCUs built from the same code, so host, mainboard, eboard and IFS switch together.

## Sources

- `extracted\main-update\control-extracted\` (control package): `AD5X.bin`, `ADM_App.hex`, `run.sh`, flash tools
- `extracted\software-3.1.6\`: `printer.base.cfg`, FlashForge klippy files, `firmwareExe`
- `factory-full\usr\prog\config\printer.cfg`: extruder section (`factory-full\usr\data\config\` is ZMod-modified)

## Board

- Mainboard `FFP0302_Main_Board_V3.0.0`, 2024-9-22 (photo: wiki.flashforge.com/resource/pictures/ad5x_picture/ad5x_introduction/pic13.png, 825x668, MCU marking not readable)
- MCU: square QFP right of the SoC; SoC under a shield frame left of centre
- JTAG header at the top edge next to USB-C (likely SWD to the N32), `GND TX RX` header (J33) bottom middle, 3 stepper drivers with heatsinks

## MCUs

| | mainboard `mcu` | toolhead `eboard` |
|---|---|---|
| Host port | `/dev/ttyS2`, 230400 | `/dev/ttyS5`, 230400 |
| Firmware | `AD5X.bin` | `ADM_App.hex` |
| Build | `?-20241125_172251-ubuntu` | `?-20241122_134741-ubuntu` |
| MCU (reported) | `stm32f103xe`, 144 MHz | `stm32f103xe`, 144 MHz |
| Serial pins | PA10/PA9 (USART1) | PA10/PA9 (USART1) |
| App address | `0x08000000` (no FlashForge bootloader) | `0x08010000` (64 KB bootloader) |
| Flash tool | `NationsCommand -c -d --fn AD5X.bin --v -r` | `IAPCommand ADM_App.hex /dev/ttyS5` |
| Initial SP | `0x20020000` | `0x20020000` |

- Both are Nations N32G45x: they use N32 ADC1 (`0x40020800`) and never STM32 ADC1 (`0x40012400`), and the stack at `0x20020000` needs 128 KB RAM (STM32F103xE / GD32F303xE have 64 KB)
- Kalico's N32G45x build also reports `stm32f103xe`
- Build info from the zlib data dictionary inside each firmware

### Clock (all three boards: mainboard, eboard, IFS)

- Decompiles: `re/mainboard.c`, `re/eboard.c` (+ `_v.c` with literal values), Ghidra project `re/proj`, scripts `re/scripts` (`run_decomp.sh <name> <load addr>`, `run_list.sh`)
  - mainboard `re/mainboard.bin` = `AD5X.bin`, load `0x08000000`, 234 functions
  - eboard `re/eboard.bin` from `ADM_App.hex`, load `0x08010000`, 220 functions
- Nations SDK `SystemInit` (mainboard `mainboard_v.c:4215`, eboard `eboard_v.c:4520`, same in IFS):
  - HSE on, `CFGR &= 0xf7c0ffff; CFGR |= 0x081f0000`: PLL source HSE, HSE/2, PLLMULFCT 0x17 = x24, so 12 MHz crystal -> 144 MHz
  - `CFGR |= 0x2000 | 0x500`: APB2 /2 (72 MHz), APB1 /4 (36 MHz)
  - FLASH latency 4
  - no HSE: `SystemCoreClock = 8000000` (HSI)
- kalico-ad5x: N32G45x uses the generic STM32F1 `clock_setup()` (`src/stm32/stm32f1.c:72`), `CLOCK_FREQ` is fixed (no prompt) at 128 MHz for N32G45x (`Kconfig:233`)
  - with `STM32_CLOCK_REF_12M`: div = 128/6 = 21, > 16 so halved to 10, HSE x10 = 120 MHz while Kalico assumes 128 MHz (~6.7% timing error)
  - also sets flash latency 2 and APB1 /2 (stock: 4 and /4)
- mainline Klipper (Klipper3d/klipper master) has its own N32G45x clock code in `src/stm32/stm32f1.c` (N32 power register `PWR_BASE + 0x0c`, latency from the clock, APB /4 above a limit) and `default 144000000 if MACH_N32G45x` (`Kconfig:219`); with 12 MHz: div 24 -> HSE x12 = 144 MHz
  - patch for kalico-ad5x: bring in mainline's N32G45x clock code and 144 MHz default

### Flashing

- Mainboard: `NationsCommand` = Nations N32 ISP over the chip's ROM bootloader on `/dev/ttyS2` at 115200, toggles BOOT0/RESET through host GPIOs (`/sys/class/gpio`). GPIO numbers not found yet. Recovery always possible from the host, no SWD needed
- Eboard: FlashForge IAP bootloader at `0x08000000`-`0x0800FFFF`, app at `0x08010000`
  - plain reset: the bootloader stays in IAP mode (flash over ttyS5)
  - `BKP->DR1 = 0x1234` + reset: the bootloader skips IAP and starts the app at once (stock code at `0x08016860`: PWR/BKP clocks on, `PWR_CR.DBP` via bit-band `0x420E0020`, `BKP->DR1 = 0x1234` at `0x40006C00 + 4`, `NVIC_SystemReset()`), used for Klipper's `reset` command
  - the bootloader does not start an app whose initial stack pointer is `0x20010000` (64 KiB RAM); stock and kiln-os use `0x20020000`
  - (source for the meaning of DR1 and the stack check: kiln-os patches 0001-0003, see below)

## Test builds (WSL)

- Tools: `make` 4.4.1 (apt, `wsl -u root`), Arm GNU Toolchain 14.2.rel1 in `~/arm-toolchain` (`INSTALLED.md` there)
- Build script copies `Desktop\kalico-ad5x` to `~/kalico-build`, converts the copy to LF (the Windows checkout is CRLF, make needs LF), `.config` from `free-ad5x`, `make olddefconfig`, `make`. Output in `~/kalico-out/<board>/` (klipper.bin, .elf, .dict, .config). The repo itself is not touched
- Mainboard (2026-10-23, `kalico-mainboard.config`, kalico-ad5x with patches 1-5): builds, `klipper.bin` 37104 B, version `v2026.10.00-160-ge5e1da62-dirty` (dirty = LF conversion)

| | ours | kiln-os mainline | stock `AD5X.bin` |
|---|---|---|---|
| size | 37104 | 41432 | 37504 |
| SP | `0x20020000` | `0x20020000` | `0x20020000` |
| reset | `0x08006871` | `0x08006cdd` | `0x08006ddd` |
| MCU / CLOCK_FREQ / baud | stm32f103xe / 144 MHz / 230400 | same | same |
| serial pins | PA10,PA9 | same | same |

- Eboard (2026-10-23, `kalico-eboard.config`): builds, `klipper.bin` 37512 B, `klipper.hex` from `arm-none-eabi-objcopy -O ihex klipper.elf` (in `~/kalico-out/eboard/`), version `v2026.10.00-160-ge5e1da62-dirty-20261023_062032-bob`

| | ours | kiln-os `eboard.hex` | stock `ADM_App.hex` |
|---|---|---|---|
| load | `0x08010000` | `0x08010000` | `0x08010000` |
| size | 37512 | 41428 | 36012 |
| SP | `0x20020000` | `0x20020000` | `0x20020000` |
| CLOCK_FREQ / baud | 144 MHz / 230400 | same | same |
| hex records | type 4 `0x0801`, 16-byte data, type 5, EOF, CRLF | same | same (some 8/12-byte records) |

- `command_reset` disassembly: PWR/BKP clocks on (`RCC+0x1c |= 0x18000000`), `PWR_CR |= DBP`, `BKP(0x40006C00)+4 = 0x1234` (movw), DBP off, `NVIC_SystemReset` (patch 3 is in)

### Eboard bootloader / IAPCommand

- After a reset the bootloader waits on ttyS5 at 115200 and prints `Ready` lines; `A` (0x41) -> ACK (0x06) and it starts the app (openad5x `startup.sh` `eboard_start()`)
- `IAPCommand` = "stm32isp": `stm32isp [Options] <file> <comport> <baudrate>`, `-verbose`, reads Intel-hex, uses `/sys/class/gpio` (probably eboard reset), strings mention `/Update`. Stock: `IAPCommand ADM_App.hex /dev/ttyS5`
- Tried 2026-10-23 with the stock eboard app running:
  - `IAPCommand -verbose eboard.hex /dev/ttyS5` (115200): "Can not connect to board, timed-out", nothing written, no GPIO reset attempt
  - Klipper `reset` to the stock app (script with FlashForge's `serialhdl`, 230400): sent fine, but afterwards no `Ready` at 115200: the stock app resets with the BKP DR1 0x1234 bypass and goes straight back to the app
  - (Klipper's `console.py` doesn't take commands from a pipe; it also kept ttyS5 locked until killed)
  - So the eboard can only be flashed while its bootloader waits after power-on, before `eboard_start` sends `A`: needs a boot hook (stock FlashForge also flashes it at boot, in `run.sh`)
- Boot hook (openad5x `startup.sh`, on the printer 2026-10-23 11:31, md5 `5a3d239d4cff96654c66e0b9e68c0641`; old one saved as `/usr/data/kalico-fw/startup.sh.before-eboard-flash`):
  - in `eboard_start`, after `Ready`: if `/usr/data/kalico-fw/eboard.flash` exists, read the hex path from it, delete it, run `IAPCommand <hex> /dev/ttyS5` (log `/usr/data/logs/openad5x/eboard-flash.log`), reopen ttyS5 and go round the loop again (`A` if the bootloader still waits, "application already running" if not)
  - flag set 2026-10-23 11:31: `eboard.flash` = `/usr/data/kalico-fw/eboard.hex` (md5 `d43395d0725e73059f2fa22af890eefa`)
  - way back: `echo /usr/prog/PROGRAM/control/1.1.1/ADM_App.hex > /usr/data/kalico-fw/eboard.flash`, reboot

### Eboard flashed (2026-10-23 11:32, power cycle)

- `openad5x.log`: `eboard: flashing /usr/data/kalico-fw/eboard.hex`, `eboard: IAPCommand exit 0`, `eboard: application started`
- `eboard-flash.log`: 36 frames, `STM32Write: success.`, `STM32iap finished NA.`; IAPCommand also runs `rm /usr/prog/PROGRAM/control/Update` (stock tool behaviour)
- flag file deleted by the hook
- FlashForge's stock Klipper now: "MCU Protocol error", both MCUs listed with our versions (`mcu` ...055547-bob, `eboard` ...062032-bob), cause `mcu 'eboard': Unable to extract params from: config_lis2dw` (FlashForge's `[lis2dw]` host module sends an older `config_lis2dw` than Kalico's firmware). Expected; goes away with Kalico on the host
- Same boot: first power-cycle test of `startup.d/05-entware.sh` passed (`05-entware.log` "started", exit 0, `/opt` mounted, `/opt/bin/gcc` there, NaN byte 0x01)

### Mainboard flashed (2026-10-23 11:13)

- `klipper.bin` (md5 `b1533104d38ba84bb674740c147649be`) copied to `/usr/data/kalico-fw/mainboard.bin`
- `/usr/prog/klipper/klipperDaemon stop`, then from `/usr/prog/PROGRAM/control/1.1.1`: `./NationsCommand -c -d --fn /usr/data/kalico-fw/mainboard.bin --v -r`
  - ISP at 9600 baud, BOOT Command Version V22, SubVersion V25, UID `0xa011150415047353336125`, erase all, download, "Chip verification succeeded", reset, exit 0
  - NationsCommand also runs `rm -f <its own dir>/UpdateM`: it deleted the 0-byte `/usr/prog/PROGRAM/control/1.1.1/UpdateM`
- Start Klipper with `/usr/prog/klipper/start.sh`, not `klipperDaemon start` directly: start.sh sets `LD_LIBRARY_PATH` for FlashForge's Python, without it klippy dies at once without writing a log
- Result with FlashForge's stock Klipper (host) + stock eboard:
  - `Loaded MCU 'mcu' 137 commands (v2026.10.00-160-ge5e1da62-dirty-20261023_055547-bob / gcc: (Arm GNU Toolchain 14.2.Rel1 ...) 14.2.1)`, `Configured MCU 'mcu' (1024 moves)` (stock: 116 commands, 4096 moves)
  - no protocol error, klippy `ready`
  - Moonraker `/printer/objects/query?mcu`: `mcu_version` = ours, `CLOCK_FREQ` 144000000, measured `freq` 144000685 (clock patch works; without it ~120 MHz)
- Way back: same command with `/usr/prog/PROGRAM/control/1.1.1/AD5X.bin` (md5 `522b4641821016952cd4504e4c2177ed`, same as the dump)
- Not tested yet: any motion, heaters, endstops, TMC UART with this firmware

## kiln-os (djvalic/kiln-os, GPL-3.0)

"Open firmware for the Flashforge AD5X: mainline Klipper, Linux 6.6, recovery OS, one-click updates". `klipper/` folder:
- Both boards flashed with mainline Klipper `v0.13.0-803-g4cd711119` (`mcu-dicts/FLASHED`, firmware in `mcu-firmware/`)
- `mcu-configs/ad5x-mainboard.config`: `MACH_N32G455xE` (xblax/klipper Kconfig), `CLOCK_FREQ=144000000`, `STM32_CLOCK_REF_12M`, `STM32_FLASH_START_0000`, USART1, 230400, `RAM_SIZE=0x20000`
- `mcu-configs/ad5x-eboard.config`: same with `MACH_N32G455xC`, `STM32_FLASH_START_10000`
- `*.mainline.config`: same for mainline (`MACH_N32G455`, `RAM_SIZE=0x10000` before patch 0003)
- So both boards are N32G455 (mainboard xE, eboard xC)
- `mcu-patches/` (mainline Klipper):
  - 0001 (xblax): `command_reset` on N32G455 + 64 KiB bootloader writes `BKP->DR1 = 0x1234` then resets (bootloader bypass, fixes FIRMWARE_RESTART)
  - 0002 (xblax): `bootloader_request` on N32G455 + 64 KiB bootloader = plain `NVIC_SystemReset()` (bootloader stays in IAP by default)
  - 0003: `RAM_SIZE 0x20000 if MACH_N32G455` (eboard bootloader checks the stack pointer)
- Also an IFS module (`klipper/extras/ifs.py`, `ifs.cfg`): keeps the stock IFS firmware and translates to F-commands over ttyS4 (not our approach, we replace the IFS firmware); host-side patch `patches/trsync-timeout-50ms.patch`

## Kalico build configs (drafts)

- `kalico-mainboard.config`: N32G455, no bootloader (`STM32_FLASH_START_0000`), 12 MHz, USART1 PA10/PA9, 230400
- `kalico-eboard.config`: same, 64 KiB bootloader (`STM32_FLASH_START_10000`)
- `../ifs/kalico.config`: N32G455, 64 KiB bootloader, 12 MHz, USART1, 115200
- Kalico patches needed:
  1. clock: mainline Klipper's N32G45x clock code + 144 MHz default (all three boards)
  2. RAM_SIZE 128 KiB for N32G455 (eboard bootloader stack check; stock IFS also uses a stack above 64 KiB? its SP is `0x20007498`, so not needed there)
  3. eboard: `command_reset` = BKP DR1 0x1234 + reset, `bootloader_request` = plain reset
  4. IFS bootloader request: erase page `0x0800D000` + reset (see `ifs/index.md`)
  5. IFS RS485 direction on PA11 (see `ifs/index.md`)

### FlashForge-only MCU commands (not in Kalico)

- `Mainboard`, `Exboard`: board identification strings (stock `checkEboard`)
- `set_radar_interval`, `set_radar_sync_pulse`: unknown, "radar"
- `i2c_modify_bits`, `i2c_set_software_bus`, `spi_set_software_bus`: older Klipper bus commands

## Pins (stock config)

### Mainboard

| Function | Pins |
|---|---|
| stepper_x | step PB13, dir PB12, enable !PB1, TMC2209 uart PB11, endstop `!eboard:PA15` |
| stepper_y | step PC4, dir PA7, enable !PA2, TMC2209 uart PB0, endstop !PC12 |
| stepper_z | step PC7, dir PC8, enable !PB14, TMC2209 uart PB15, endstop PD2 |
| heater_bed | heater PB9, sensor PA0 (Generic 3950, 4700 pullup), max_power 0.4 |
| probe | !PB3 (load cell trigger, the load cell itself is on host ttyS7) |
| chamber LED | PA11 |
| pcb_fan | PA5 |

- X/Y/Z TMC2209: sense_resistor 0.10, X/Y run 1.1 hold 0.9, Z run 0.9 hold 0.9
- corexy, rotation_distance X/Y 40, Z 8, microsteps 16

### Eboard

| Function | Pins |
|---|---|
| extruder | step PB14, dir !PB15, enable !PB12, TMC2209 uart PB10 (run/hold 0.8, sense 0.10) |
| extruder heater | heater PA8, sensor PA0 (Generic 3950), max_temp 350 |
| heat_fan (hotend) | PB4 |
| fanM106 (part) | PB5 |
| lis2dw accelerometer | cs PA4, software SPI sclk PA5 / mosi PA7 / miso PA6 |
| filamentValue sensor | PA3 (read as Generic 3950 temperature sensor) |
| cutValue sensor | PA2 (read as Generic 3950 temperature sensor) |
| X endstop | PA15 |

- extruder: microsteps 16, gear_ratio 50:10, rotation_distance 21.9, pressure_advance 0.04

## FlashForge host-side changes

- `firmwareExe` (FlashForge's own program) opens ttyS2, ttyS3, ttyS4 (IFS), ttyS5, ttyS7 (load cell)
- Replaced klippy files in `software-3.1.6`:
  - `query_adc.py`: `QUERY_ADC`, `GET_FILAMENT_VALUE`, `GET_CUT_VALUE` (eboard PA3/PA2)
  - `virtual_sdcard.py`: `SDCARD_CLEAR_REFUELLING`, `SDCARD_SET_CHANNEL`, `SDCARD_ENABLE_FFM` (IFS print integration with firmwareExe)
  - `extruder.py`, `exclude_object.py`: modified versions
- Extra module: `extras/bl24c16f.py` (EEPROM)

## Host: Kalico klippy on the AD5X

- CPU Ingenic X2600, mips32r2, NaN2008, FP64, glibc 2.33 (rootfs `lib/ld-2.33.so`, `lib/libc-2.33.so`, `/lib/ld-linux-mipsn8.so.1`), no gcc on the printer
- (glibc 2.29 in openad5x readme.plan is mjpg-streamer's build toolchain, not the printer)
- Python: FlashForge's `/usr/prog/Python-3.8.2` (Moonraker already runs on it)
- Kalico source: `kalico-ad5x` (FlashForge-C5-Modding-Group, KalicoCrew upstream)

### Python version

- `kalico-ad5x/pyproject.toml`: `requires-python = ">=3.9"`
- klippy will not start on 3.8: `printer.py:664` calls `compat.install()` on every start, which uses `str.removeprefix` (3.9+) in `compat.py:31` and `:67`
- Also 3.9+: `configfile.py:164` (`removeprefix`, python script config values), runtime `list[...]` / `tuple[...]` annotations without `from __future__ import annotations` in `extras/nozzle_cleanup.py`, `extras/probe_eddy_current.py`, `extras/load_cell/ads1220.py`, `extras/load_cell/hx71x.py`
- So the host needs Python >= 3.9 built for mips32r2 / NaN2008 / FP64, or klippy patched for 3.8

### Python 3.13 hard-float build (FlashForge-C5-Modding-Group/opencreator-fs)

- Release `python-3.13-hardfloat-r2` (2026-10-16), asset `python-hf-c5-release.zip` -> `python-hf-c5.tar.gz`, "meant only for FlashForge devices, such as the Creator 5/Pro and AD5X"
- BUILDINFO-c5: Python 3.13.9, prefix `/usr/data/python-hf`, numpy 2.2.2, greenlet 3.3.2, cffi 2.0.0, toolchain Ingenic MIPS GCC 12.1 Release 6.0.0 (xburst2, glibc 2.33), kalico `FlashForge-C5-Modding-Group/kalico` @ `3250f3bff229276f52a5e4c2d0ce1c09b8fc0ddb` (that repo is the C5's Kalico; the AD5X uses `kalico-ad5x`)
- `bin/python3.13`: flags `0x70001405`, NaN2008, FP64, interp `/lib/ld-linux-mipsn8.so.1` (same as firmwareExe)
- `lib/libpython3.13.so.1.0` needs up to GLIBC_2.33: matches the AD5X rootfs
- site-packages: cffi, greenlet, jinja2, markupsafe, numpy, pycparser, serial (pyserial), dbus_fast: all Kalico host packages
- Own libs: libffi, libssl/libcrypto 3, libsqlite3, liblzma, libbz2, libjpeg, libsodium, libatomic, libgcc_s
- `cc/bin/gcc`: shell wrapper around Entware gcc (`${ENTWARE_GCC:-/opt/bin/gcc}`) adding `-mabi=32 -mips32r2 -mhard-float -mfp64 -mnan=2008`, bundled glibc headers and crt files (`cc/lib`, `cc/include`): lets klippy build `c_helper.so` on the printer, needs Entware gcc in `/opt`

### c_helper.so

- `klippy/chelper/__init__.py` `get_ffi()` compiles `c_helper.so` with `gcc` on first start when sources are newer than the .so (`check_build_code`)
- No gcc on the printer: `c_helper.so` has to be cross-built (glibc, mips32r2, NaN2008, FP64, `-Wall -g -O2 -shared -fPIC`) and shipped with a newer mtime than the sources
- Sources: `pyhelper.c serialqueue.c stepcompress.c steppersync.c itersolve.c trapq.c pollreactor.c` + kinematics files in `SOURCE_FILES`

### Python packages (`kalico-ad5x/pyproject.toml` vs FlashForge Python 3.8.2)

| Package | Kalico (py < 3.12) | FlashForge has |
|---|---|---|
| cffi | 1.15.1 | 1.13.1 |
| greenlet | 2.0.2 | 3.0.3 |
| Jinja2 | >= 3.1.6 | 2.10.3 and 3.1.2 (3.1.2 may be from ZMod, the dump is from a ZMod printer) |
| markupsafe | 2.1.5 | 1.1.1 and 2.1.1 (same) |
| numpy | ~= 2.0 (py 3.9) | 1.16.4 |
| pyserial | 3.4 | 3.4 |

- With a new Python (>= 3.9) these packages have to be built for it too (cffi, greenlet, markupsafe, numpy have C parts)

- Paths: `factory-full/usr/prog/Python-3.8.2/lib/python3.8/site-packages`

## Open

- Host GPIO numbers for mainboard BOOT0/RESET (from `NationsCommand` code or an strace on the printer)
- kalico-ad5x has no `MACH_N32G455xE` / `xC` sub-variants (those come from xblax/klipper); check what they change vs plain `MACH_N32G455`
- What `set_radar_*` is used for
- What ttyS3 is
- Load cell protocol on ttyS7 (only needed if we want weighing; probe trigger is a plain pin, PB3)
- Host Python: use the opencreator-fs Python 3.13 hard-float build (test on the AD5X)
- Entware installed 2026-10-23 (same method as C5 group `touchscreen-installer` `common/install-entware.sh`):
  - kernel package 2.0.1: legacy NaN byte `busybox devmem 0x00a130d1 8 1`
  - files in `/usr/data/bin/opt`, `mount --bind /usr/data/bin/opt /opt`
  - `generic.sh` from `http://bin.entware.net/mipselsf-k3.4` (glibc 2.27 packages, loader `ld.so.1`), base 18 packages
  - `opkg install gcc`: OpenWrt GCC 8.4.0 (~35 MB), headers from `include/include.tar.gz` in `/opt/include`
  - gcc rejected every option at first: the install leaves a 0-byte `specs` file in `/opt/lib/gcc/mipsel-openwrt-linux-gnu/8.4.0/`, and with a specs file present the driver skips its built-in specs. Fixed by `mv specs specs.empty`. A gcc reinstall recreates it. gcc needs `/opt/bin` on PATH. Packages gcc 8.4.0-8, libgcc 8.4.0-12, binutils 2.45.1-1, libc 2.27-12
- Python 3.13.9 installed at `/usr/data/python-hf` (2026-10-23): runs, cffi / greenlet / jinja2 / markupsafe / numpy / serial import (markupsafe has no package metadata, harmless)
- Compile test passed: python-hf wrapper + Entware gcc builds a hard-float NaN2008 .so (`0x70001407`, mips32r2, FP64) with Kalico's flags, Python 3.13 loads it with cffi. klippy needs `PATH=/usr/data/python-hf/cc/bin:$PATH:/opt/bin`. Details in `openad5x/readme.plan`
- Real c_helper.so: kalico-ad5x `klippy/chelper` + `chelper.get_ffi()` on the printer builds it in ~46 s (305 KB, nan2008, FP64), loads, `trapq_alloc()` works (2026-10-23)
  - `/usr/data` free: 2.2 GB before, 1.7 GB after
  - NaN byte and bind mount are lost on reboot: needs a startup.d script (NaN byte, bind mount, `/opt/etc/init.d/rc.unslung start`)
- Stock printer Jinja2/MarkupSafe versions (without ZMod)

## Eboard PB1 power (2026-10-24)

- Hotend heater did not heat under Kalico: `power 1.0`, temperature stayed 24 C, verify_heater shutdown `Heater extruder not heating at expected rate`
- Stock eboard firmware `FUN_08014bdc` (called from init `FUN_08012...` before the main loop): GPIOB clock on, PB1 + PB7 Out_PP, both set high (BSRR `FUN_08016b88`). PB1 stays high; PB7 is cleared later in the main loop (`FUN_08016b8c` = BRR) once a flag is set. Neither pin is in the Klipper config, so under Kalico they float
- `firmwareExe` host GPIOs (`gpio_out`) are only used by `doPowerOff` / `printCompletedPowerOff` and `sLightCheck`, not for heaters
- PB1 alone did not help. PB7 is the hotend heater power enable: with PB7 high the heater went 24 -> 62 C in 15 s and held 60 (2026-10-24)
- Config: `[static_digital_output eboard_power]` `pins: eboard:PB1` (stock always high) and `[output_pin heater_power]` `pin: eboard:PB7`, `value: 1`, `shutdown_value: 0` (stock also drops PB7 later; shutdown cuts heater power). Backup `printer.cfg.before-pb1`
- Stock mainboard firmware only has PC0 (load cell `level_res`) as a fixed output
- Bed heater works under Kalico unchanged (2026-10-24): M140 S50, 25->34 C in 30 s at max_power 0.4, no extra power pin

## pcb_fan (2026-10-24)

- `[fan_generic pcb_fan]` on `PA5` (stock config) stays off until `SET_FAN_SPEED`. Under Kalico nothing sent it: Y TMC2209 overtemp shutdown (`ot=1 t120`) mid-print
- Stock firmwareExe (`firmwareexe/pcbfan.c`, Ghidra string refs): `SET_FAN_SPEED FAN=pcb_fan SPEED=1` in `SerialObject::serialPrint` before `M24`, `SPEED=0` in its end/cancel cleanup; also 1 then 0 in `FourToOne::changeStart` (IFS change), `Filament::dryingStart`, auto calibration; manual toggle in More Info
- No SoC temperature to drive it: X2600 kernel has no thermal/hwmon driver, `/module_driver` has none, stock never read one
- Kalico `printer.base.cfg`: `[controller_fan pcb_fan]` `pin:PA5` `heater: extruder` (all steppers by default): on while any motor is enabled or the hotend heats, off 30 s after idle. Covers prints, IFS changes and cancels like stock. Backup `printer.base.cfg.before-pcbfan`
