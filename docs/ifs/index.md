# AD5X IFS firmware RE notes

Goal: replace the stock IFS firmware with our own (Kalico MCU).

## Input

- `ifs.bin` copied from `extracted\main-update\control-extracted\ifs.bin`
- sha256 `378af71ac647e5865f70e096193acdb19642860a3408457e3b2a44cf01e1c01f`, 41168 bytes
- F19 reply: `four color. version: 3.0.7`
- `factory-full\usr\prog\PROGRAM\control\1.0.6\ifs.hex` is an older, different build

## Ghidra (12.2, headless)

- Project `free-ad5x/ifs/proj/ifs`, decompile `free-ad5x/ifs/ifs.c` (243 functions)
- Loaded raw: `-loader BinaryLoader -loader-baseAddr 0x08010000 -processor ARM:LE:32:Cortex`
- Scripts: `free-ad5x/ifs/scripts/ExportDecomp.java` (vector table + full decompile), `ListRange.java` (disassemble/list a range, xrefs)

## Memory layout

- App at `0x08010000`, size 0xA0D0
- Bootloader at `0x08000000`-`0x0800FFFF` (not in the file)
- Initial SP `0x20007498`, so >= 30 KB RAM
- Flag page at `0x0800D000` (inside the bootloader area)

## Bootloader entry: F37

- Command parser `FUN_08012de8`: parses `F<n>`, `tbh` jump table at `0x08012e3a`, index = n - 10
- F37 (case 27, code at `0x0801378a`):
  1. `FUN_08011fe0(0x0800D000, 0xFFFFFFFF)`: flash unlock, clear status (0x35), erase page `0x0800D000`, program word `0xFFFFFFFF`, lock
  2. set FAULTMASK, write `SCB->AIRCR = 0x05FA0004 | (AIRCR & 0x700)` (system reset)
- So the app wipes its "app valid" flag and resets, the bootloader then waits for `IFSCommand`
- Stock `run.sh`: `ifsF37 /dev/ttyS4` then `IFSCommand ifs.hex /dev/ttyS4`
- Our firmware must implement F37 the same way, or re-flashing over ttyS4 is lost (SWD only)

## Host protocol (ttyS4, 115200 8N1, text)

- Command + `\r\n`, wait ~0.2 s, `0xFF`, read one reply line
- F13 status: `FFS_state: %d silk_state: %d chan: %d ffs_channels_insert: %d stall_state: %d jinsi_GCONF: ... qiehuan_GCONF: ...`
- F10 feed, F11 exit (unload), F23/F24 select chan, F39 release, F12 sensors, F14/F40 stall, F19 version, F22 insert, F30, F112
- F41-F64: TMC register reads (GCONF, GSTAT, DRV_STATUS, CHOPCONF, PWMCONF)

## Peripherals referenced (literal pool scan)

- GPIOA `0x40010800`, GPIOB `0x40010C00`, GPIOC `0x40011000`, AFIO, EXTI
- USART1 `0x40013800`, USART2 `0x40004400`, USART3 `0x40004800`
- TIM1, TIM2-7, TIM8, `0x40015000`/`0x40015400` (TIMER9/10 on GD32F30x / XL STM32F1)
- DMA1 `0x40020000`, RCC `0x40021000`, FLASH `0x40022000`, PWR

## Board: FFP0302_Main_Board_V1.0.4 (2024-08-05), FlashForge part 20004780001

Photos: `free-ad5x/ifs/board/ifs1.jpg` (back), `ifs2.jpg` (front), from 3dprima.com product page

- U5 Nation N32G455, X1 12.000 MHz crystal
- U3, U4 stepper drivers, marking reads MS35776 (TMC2209-compatible UART clone, to verify)
- U1 GM3085E RS485 transceiver
- J1 "485-IN" 4-pin Microfit: 24V, GND, A, B
- J2-J5 Silk1-Silk4: GND, VCC, Speed, Silk (per slot: filament present + movement)
- Zero_CHK: SIG, VCC, GND (selector home, PB9)
- J8 "A", J7 "B": motor connectors, R500 sense resistors
- J9: VCC, CLK, DIO, GND = SWD (recovery path with ST-Link)
- J6: 3-pin, back side, unlabelled
- D4 OK, D5 ERR LEDs

## Chip: Nations N32G455

- ADC init (`FUN_08011a2c`) uses `0x40020C00`, `0x40021800`, `0x40021C00` = N32G45x ADC2/3/4 exactly (Kalico `lib/n32g45x/include/n32g45x_adc.h`), ADC3/4 are G455 only

- UART at `0x40015400` (PC4/PC5, 9600): a timer on STM32F1/GD32F30x, UART7 on N32G45x
- Clock: `CFGR |= 0x30000 | 0x081C0000` = HSE/2 x24 (PLLMUL bit 4 at bit 27), 12 MHz crystal gives 144 MHz (N32G45x max, GD32F303 max is 120)
- ADC on PB12-15: ADC3/4 pins, N32G455 only (Kalico `src/stm32/n32g45x_adc.c`)
- Hardware FPU used (vldr/vmov d0): Cortex-M4F
- Kalico supports it: `MACH_N32G455`, reports itself as `stm32f103xe`, `STM32_FLASH_START_10000` (64 KiB bootloader offset); default `RAM_SIZE 0x10000` for N32G45x
- The AD5X mainboards report `stm32f103xe` at 144 MHz, so they are probably N32G45x too

## Pins (StdPeriph GPIO_Init = `FUN_08011858`, `FUN_08011984` = BSRR (high), `FUN_08011980` = BRR (low), ReadBit `FUN_0801196e`)

| Pin | Mode | Use |
|---|---|---|
| PA9 / PA10 | AF_PP / IPU | USART1 TX/RX, 115200: host link (ttyS4) |
| PA11 | Out_PP, low at init | RS485 direction for USART1: high = transmit, low = receive (`FUN_08011984` = BSRR before reply in `FUN_08019e50`, `FUN_08011980` = BRR in DMA1 TX-complete `vec_30`) |
| PA2 / PA3 | AF_PP / IPU | USART2 TX/RX, 9600, DMA1 (rx buf `0x2000153c`): feed TMC "jinsi" |
| PC4 / PC5 | AF_PP / IPU | UART7 TX/RX, 9600, DMA2 (rx buf `0x20001564`): selector TMC "qiehuan" |
| PA0 | Out_PP | feed motor STEP (`FUN_08018798`; motor table `0x20000358` +0 in `ram_init.bin`) |
| PA1 | Out_PP | feed motor DIR, per-motor invert flag (`FUN_0801856c`, table +8) |
| PA5 | Out_PP | feed motor EN, active low: high at init and in F112 stop, low to enable (`FUN_080186a0`, table +0x10, enable mask `0x20000437`) |
| PA7 | Out_PP | selector motor STEP, toggled per tick (`FUN_0801900c` state machine) |
| PA6 | Out_PP | selector motor DIR: high = positive (count up) and home seek, low = back off |
| PB1 | Out_PP | selector motor EN, active low: low while moving, high at init, on arrival and in F112 stop |
| PB9 | IPU | selector home sensor, 0 = triggered |
| PB5 (high), PB6 (low) | Out_PP | unknown (LEDs?), only set at init (`FUN_08011b48`) |
| PC0 / PC2 / PB12 / PB14 | analog | Silk1-4 filament sensors (ADC2 ch6, ADC2 ch8, ADC4 ch3, ADC4 ch4) |
| PC1 / PC3 / PB13 / PB15 | analog | Speed1-4 movement sensors (ADC2 ch7, ADC2 ch9, ADC3 ch5, ADC4 ch5) |

- ADC loop `FUN_08015ea0`: each input averaged over 20 samples
- Silk: flag set when average < 900 or > 3100, cleared when 1001-2999 (`0x200001bf[0..3]`), rising edge sets bit in `0x200001d0` (= `ffs_channels_insert`)
- Speed: window 1400-2636 / 1200-2800, values also logged to ring buffers `0x2000139c`.. (movement detection, feeds `stall_state` via `0x200001d9`)
- Slot order (bit 0-3 = slot 1-4) assumed to match Silk1-4 connector numbering, to verify

## Selector (`FUN_0801900c`, state `0x200001b0`, step count `0x200001e0`, target `0x2000021b`)

- Bit-banged, one step = STEP high then low, count +1/-1 per step
- Forward (count up) = PA6 DIR high, back = PA6 low (with GCONF shaft=1; Kalico shaft=0 so `dir_pin: !ifs:PA6`)
- EN (PB1) low while moving, high on arrival: motor off when parked (IHOLD=0 too), held by the mechanism
- Homing (states 1-4):
  1. if home sensor (PB9) already triggered (0): back off (DIR low) up to 4096 steps until it clears, error 0x7e if not
  2. forward (DIR high) up to 16384 steps until PB9 = 0, error 0x7e if not found
  3. count = 0 at the sensor
- Positions (steps from home, 8 microsteps):

| Target | State | Position | Meaning |
|---|---|---|---|
| 1 | 7 | 0 | slot 1 |
| 0 | 0xc | 2048 | neutral (no slot) |
| 2 | 0x12 | 4096 | slot 2 |
| - | 0x17 | 6144 | neutral |
| 3 | 0x1d | 8192 | slot 3 |
| - | 0x22 | 10240 | neutral |
| 4 | 0x28 | 12288 | slot 4 |
| - | 0x2d | 14336 | neutral |

- 16384 steps = one full turn: slots every 90 degrees, neutral positions halfway (45 degrees) between
- 16384 microsteps at MRES 8 = 2048 full steps per turn (geared)

## TMC driver setup (`FUN_08011bc8`, same for both drivers)

- Write `FUN_08019d1e(uart, reg, val)`: TMC2209 datagram, sync 0x05, slave addr 0, reg|0x80, 4 bytes, CRC8 (`FUN_080164e4`)
- Read `FUN_08019c18(uart, reg)`
- Each driver has its own UART, separate TX/RX pins, 9600 baud

| Reg | Value | Decoded |
|---|---|---|
| GCONF 0x00 | `0x1dc` | en_spreadcycle=1, shaft=1, index_otpw=1, pdn_disable=1, mstep_reg_select=1, multistep_filt=1, I_scale_analog=0 |
| IHOLD_IRUN 0x10 | `0xa0900` | IHOLD=0, IRUN=9, IHOLDDELAY=10 |
| TPOWERDOWN 0x11 | `0x80` | 128 |
| CHOPCONF 0x6c | `0x150082c3` | TOFF=3, HSTRT=4, HEND=5, TBL=1, vsense=0, MRES=5 (8 microsteps), intpol=1 |
| PWMCONF 0x70 | `0xc80d174b` | stealthChop settings, unused (spreadCycle on) |

- `F42 S<1|2> I<0-31>`: debug command, sets IRUN live on driver 1 (USART2) or 2 (UART7)
- Current: if TMC2209-equivalent with the R500 (0.5 ohm) resistors as sense, IRUN=9 is about 0.14 A rms. In Kalico `sense_resistor: 0.500` + `run_current: 0.138` gives CS=9, the same register value as stock, whatever the real current is

## F13 reply (case at `0x080133fc`)

- First reads GCONF (reg 0) from both TMCs (`FUN_08019c18(USART2,0)`, `FUN_08019c18(UART7,0)`)
- `FFS_state` = `0x200001b0` (selector state machine in `FUN_0801900c`, 5 = ready)
- `silk_state` = bits from `0x200001bf[0..3]`
- `chan` = `0x200000f0`, `ffs_channels_insert` = `0x200001d0`, `stall_state` = `0x200000da` (from `0x200001d9[0..3]`)
- `jinsi_GCONF` = `0x20000224` (USART2), `qiehuan_GCONF` = `0x20000238` (UART7)

- Motor table `0x20000358`: 5 entries x 0x28 (EN +0, DIR +8, STEP +0x10), all 5 = PA0/PA1/PA5 in the compiled data and never written at runtime: a generic 5-axis motion lib with one feed stepper wired
- F112 (`FUN_08015d28`) stops both motors: PA5 high, PB1 high (both enables off)

- RAM init data is Keil-compressed: region table at `0x0801a004`, src `0x0801a024` -> `0x20000000`, 0x490 bytes, decompressor `0x08010f44`. Unpacked copy: `free-ad5x/ifs/ram_init.bin`

## Test build (2026-10-23, kalico-ad5x e5e1da62 + `kalico.config`, WSL, see `../mainboard/NOTES.md` "Test builds")

- `~/kalico-out/ifs/`: `klipper.bin` 37672 B, `klipper.hex` (`objcopy -O ihex`), version `v2026.10.00-160-ge5e1da62-dirty-20261023_171001-bob`
- `.config`: `MACH_N32G455`, `CLOCK_FREQ 144000000`, `CLOCK_REF_FREQ 12000000`, `FLASH_APPLICATION_ADDRESS 0x8010000`, `RAM_SIZE 0x20000`, `STM32_SERIAL_USART1`, `SERIAL_BAUD 115200`, `STM32_FLASHFORGE_IFS=y`
- dict: `stm32f103xe`, 144 MHz, 115200, `RESERVE_PINS_serial PA10,PA9`, `RESERVE_PINS_rs485 PA11`
- In the binary: `0x0800D000`, `FLASH_KEY1` / `FLASH_KEY2`, FLASH base (bootloader request), `rs485_dir` (PA11)
- Hex layout same as stock `ifs.hex`: `:020000040801F1`, 16-byte data records, type 5, EOF, CRLF
- **SP: ours `0x20020000`, stock `0x20007498`.** The eboard bootloader checks the app SP (refused `0x20010000`, accepts `0x20020000`); unknown whether / how the IFS bootloader checks. If it refuses ours the IFS stays in its bootloader (stock `ifs.hex` can be flashed back with `IFSCommand`). Option: `RAM_SIZE 0x8000 if STM32_FLASHFORGE_IFS` (SP `0x20008000`)
- Done 2026-10-23: kalico-ad5x `src/stm32/Kconfig` `RAM_SIZE`: `default 0x8000 if STM32_FLASHFORGE_IFS` above the N32G455 line (uncommitted). Rebuild: `RAM_SIZE 0x8000`, SP `0x20008000`, 37672 B, version `...-20261023_173637-bob`, `~/kalico-out/ifs/klipper.hex` regenerated. Mainboard / eboard unchanged (option off)

## IFS flashed (2026-10-23 ~17:40)

- `klipper.hex` (SP `0x20008000`, md5 `a0230588a2c273507a7413086c19a32f`) -> `/usr/data/kalico-fw/ifs.hex`
- ttyS4 free (Kalico has no `[mcu ifs]` yet, firmwareExe not running)
- From `/usr/prog/PROGRAM/control/1.1.1`: `./ifsF37 /dev/ttyS4` (exit 0, no output), `./IFSCommand /usr/data/kalico-fw/ifs.hex /dev/ttyS4`: frames of 1030 bytes, `STM32Write: success.`, `STM32iap finished NA.`, exit 0
- No files deleted this time (`IFSCommand`, `ifs.hex`, `ifsF37` still in `control/` and `control/1.1.1/`)
- Way back: Kalico bootloader request (flag page patch) or, if the bootloader waits after power-on, `IFSCommand /usr/prog/PROGRAM/control/1.1.1/ifs.hex /dev/ttyS4`; `ifsF37` no longer works (Kalico doesn't know F37)
- Not checked yet: that the app starts (SP accepted) and answers Kalico on ttyS4 at 115200

## IFS on Kalico (2026-10-23 ~23:15)

- First build: no answer. PA11 polarity was inverted (stock: high = transmit, low = receive, see Pins). Fixed in `src/stm32/serial.c`
- That build couldn't hear the host, so no bootloader request. `IFSCommand` got no sync: the bootloader only listens right after IFS power-up (flag at `0x0800D000` set)
- Second build (polarity fixed): replies arrived with the first 1-2 bytes corrupted (`90d1b77e` for NAK `0516fbb77e`, uart4 `fe:` count rising). The host side switches its RS485 driver in hardware (no kernel RS485 on ttyS4) and holds the bus briefly after its last byte, Kalico answers within microseconds
- Fix: `serial.c` waits `RS485_TURNAROUND_US` (1000) after the last received byte before driving PA11 high; direction + TXEIE under `irq_save`. Also `clock_setup_n32g45x` now drops to HSI and stops the PLL first (like stock SystemInit `FUN_08012428`), and `serial_init` clears USART CR2/CR3 for the IFS
- Build `v2026.10.00-160-ge5e1da62-dirty-20261023_181343-bob`, 37832 B, hex md5 `df90aaae68737e6e1974a9329f3c6279`
- Klipper: `Loaded MCU 'ifs' 137 commands`, `Configured MCU 'ifs'`, printer ready. `[mcu ifs]` in `printer.cfg` (above SAVE_CONFIG): `serial: /dev/ttyS4`, `baud: 115200`, `restart_method: command`

### Flashing the IFS (stock `IFSCommand` protocol)

- XMODEM-like, 115200 8E1: host sends `C` until the bootloader answers 0x06 (or 0x07); frames `0x01, seq u8, len u16 LE, 1024 data (0xFF padded), CRC16-CCITT (poly 0x1021, init 0) u16 LE` = 1030 B, each ACK 0x06 / NAK 0x15; then EOT 0x04 -> 0x06. No addresses, written from `0x08010000`
- `IFSCommand` does `tcflush(TCIOFLUSH)` after every write and waits 5 s per read. Its `stm32Reboot` (gpio 34) / `stm32UpdateFLag` (gpio 35) are never called
- `iap/ifs_capture.py <IFSCommand> <hex> <out.frames>`: runs `IFSCommand` against a pty fake bootloader and saves its exact frames
- `iap/ifs_catch.py <port> <frames> <seconds>`: sends `C` every 20 ms until the bootloader answers, then the frames + EOT. Works for the power-up window (unplug/replug the IFS cable) or after a bootloader request
- Bootloader request from a running Kalico IFS: write `~ \x1c Request Serial Bootloader!! ~` at 115200 8N1 to ttyS4 (Klipper must not hold ttyS4), then run `ifs_catch.py` straight away
- `iap/ifs_probe.py <port>`: passive listen, Kalico identify at 115200/230400/57600, bootloader sync

## AFC install (2026-10-23)

- AFC-Klipper-Add-On `5ea84ea` (ArmoredTurtle main), copied to `/usr/data/AFC-Klipper-Add-On` (LF, no `.git`). `install-afc.sh` not used (expects a standard Klipper host); its steps by hand:
  - `extras/*.py` except `__init__.py` symlinked into `/usr/data/kalico/klipper/klippy/extras/` (31 files)
  - `/usr/data/ad5x-afc/AFC_IFS.py` + `AFC_Hardware-IFS.cfg`; `AFC_IFS.py` symlinked into `klippy/extras/`
  - `/usr/data/config/kalico/AFC/`: `AFC.cfg`, `AFC_Macro_Vars.cfg`, `macros/`, `mcu/` (empty), `AFC_Hardware-IFS.cfg`
  - `[include AFC/*.cfg]` in `printer.cfg` above SAVE_CONFIG (backup `printer.cfg.before-afc`)
- No extra Python packages needed (AFC imports only stdlib + klippy modules)
- Kalico ADC API: `setup_adc_sample(sample_time, sample_count)`, not `setup_minmax` (fixed in `AFC_IFS.py`)
- Python module changes need a full klippy process restart; `RESTART` / `printer/restart` keeps the old module
- `[AFC_extruder extruder]` without `pin_tool_start` for now: the toolhead filament sensor is analog (eboard PA3)
- Unit section has no `hub` (a unit `hub` must name an `[AFC_hub]`); lanes and both `AFC_stepper` sections use `hub: direct`
- Lanes without a `load` pin start with `load_state` True; `AFC_IFS` applies the first silk reading so lanes show the real state

## Half-duplex host link (2026-10-23)

- With AFC the IFS config hung klippy at `Sending MCU 'ifs' printer configuration...` forever. Replayed slowly (`console.py`) every command was fine; streamed (`iap/ifs_cfgtest.py`) it took 18 s with 956 of 975 bytes retransmitted. Klipper pipelines frames, so the host transmits while the IFS answers and both are lost. A lost IFS shutdown message leaves klippy waiting with no error
- Host fix in kalico-ad5x `klippy/chelper/serialqueue.c`: half-duplex mode, one block in flight, nothing sent (or retransmitted) until `HALF_DUPLEX_GAP` (2 ms) after the last received byte. `serialqueue_set_half_duplex()`, switched on by `serialhdl.py` when the mcu reports `SERIAL_HALF_DUPLEX=1` (IFS firmware, `src/stm32/serial.c`)
- After: config in 17 ms, 0 retransmits. Klipper ready with `[mcu ifs]` + AFC. `c_helper.so` rebuilds itself on the printer (gcc on PATH via `/usr/data/python-hf/cc/bin`)
- Several klippy instances fighting over the ports left the IFS in shutdown (`oids already allocated`). Busybox `ps` cuts the command line, so match `/proc/<pid>/cmdline`: `host/klippy_restart.sh` (on the printer `/usr/data/kalico/klippy_restart.sh`) stops every klippy.py and starts one
- `iap/ifs_flash.sh` (printer `/usr/data/kalico-fw/ifs_flash.sh`): capture frames, bootloader request, catch; Klipper must not hold ttyS4
- Build `v2026.10.00-160-ge5e1da62-dirty-20261023_183821-bob`, hex md5 `2d0001c053ef1f7baa21264e386b4c6c`
- Not enough: during AFC homing `Communication timeout during homing`, then `Lost communication with MCU 'ifs'`. The IFS still sends on its own (silk ADC 40/s, stats, trsync) and collides with the host
- Stock: every reply (`FUN_08019e50`, 17 calls) comes from the F-command parser `FUN_08012de8`, so the host is master and the IFS never talks unasked
- Same rule for Kalico (second version):
  - IFS `serial.c`: output waits on a timer and only starts 1-2 ms (`RS485_GAP_US`, `RS485_WINDOW_US`) after the last received byte; a running burst continues. Shutdown handler re-arms the timer
  - Host `serialqueue.c`: nothing sent until 2 ms after the last received byte and 4 ms (`HALF_DUPLEX_TX_HOLD`) after our own transmit ends; when idle the host writes a lone `0x7e` (the mcu ignores leading sync bytes without a NAK) so the IFS gets a turn about every 4-5 ms
- Build `v2026.10.00-160-ge5e1da62-dirty-20261023_190745-bob`, hex md5 `d695d5808414a2d5eb773194f9417a2e`
- After this: 30 s idle, retransmits unchanged (61 from startup), 0 invalid, IFS `mcu_awake` 1.7% (was 12.7%). Homing no longer times out

## Motor pins corrected (2026-10-24)

- The first pin table used swapped helper names (same mistake as PA11), so every output polarity and the feed step/enable were wrong: both motors were never enabled
- Stock motor table (`0x20000358`, `ram_init.bin`): feed step PA0, dir PA1, enable PA5 (active low); selector step PA7, dir PA6, enable PB1 (active low)
- `AFC_Hardware-IFS.cfg` now: feed `step_pin ifs:PA0`, `dir_pin !ifs:PA1` (TODO verify), `enable_pin !ifs:PA5`; selector `dir_pin !ifs:PA6`, `enable_pin !ifs:PB1`; `[static_digital_output ifs_init]` PB5 high, PB6 low like stock
- Stock slot 1 is at the home sensor (0 steps), slots every 4096 steps (90 deg), neutral 2048 steps (45 deg) after each slot
- Stock motor table has 5 planner motors, all on PA0/PA1/PA5 (one physical feed motor)
- Feed enable is active low like PB1 (`enable_pin: !ifs:PA5`; stock F112 stop drives PA5 and PB1 high). `SET_STEPPER_ENABLE` + `DUMP_TMC REGISTER=IOIN` is not a reliable check here (the reads lag the enable), which first made it look inverted. Feed confirmed moving 2026-10-24 with `!ifs:PA5`, spreadCycle, 20 mm/s; direction verified with `dir_pin: !ifs:PA1` (positive = into the IFS toward the printer)
- Kalico `stealthchop_threshold: 0` means stealthChop at all speeds (any value sets `en_pwm_mode`); stock runs spreadCycle (`GCONF en_spreadcycle=1`), so no `stealthchop_threshold` line. In stealthChop the feed driver showed `ola=1 olb=1` and the motor did not turn
- Feed steps/mm (stock planner `FUN_08017b80`, `steps = mm * cfg[0x20005ca4 + m*0x30 + 4]`, set from RAM `0x2000032c` = 343696245 / 1e6): 343.696 steps/mm at 8 microsteps, so `rotation_distance: 4.655`. F10 parses L (length), S (speed, mm/min / 60), C (channel); F-command jump table at `0x08012e3e` (F10 `0x08012ed8`, F11 `0x08013040`)
- Feed `run_current: 0.25` (vsense=0 like stock): at 0.138 it clunked (skipped steps) once the real 20 mm/s ran; 100 mm push at 20 mm/s confirmed working 2026-10-24
- Lane length: stock IFS F10/F11 only move `L` at `S` and stop (states 10-13 / 14-16, then F112); the host decides. Unload = extruder E-60 (UnloadESpace) + IFS `F11 C<chn> L70 S1200` (UnloadIFSSpace), load = `F10 C<chn> L650 S1200` until the toolhead sensor. The 4 tubes stay separate up to the 4-in-1 at the toolhead, so a lane parks ~70 mm back. AFC: `dist_hub: 70` per lane (AFC moves dist_hub, then creeps to the toolhead sensor)
- `CALIBRATE_AFC BOWDEN=` is not usable as is: for direct lanes it first retracts until the load (silk) sensor clears, and the silk sensor is at the lane inlet before the feed gear
- Measured with FORCE_MOVE (selector -45 deg onto slot 1, drive in 25 mm then 2 mm steps): 188 mm from wherever the hand-pulled tip was to the toolhead sensor trip; then parked 70 mm back
- Auto load tested 2026-10-24 on lane 2: `lane2: auto loaded, toolhead sensor after 640mm, parked 70mm back`
- Lane 1 full run measured 2026-10-24: 640 mm from the inlet stop (filament pushed in until the feed gear) to the toolhead sensor trip (stock first-load limit F10 L650); parked 70 mm back after
- Auto load on insert (`AFC_IFS.on_filament_insert`, AFC calls it for HTLF-type units after prep): like stock, feed the new lane in `auto_load_step` (10 mm) steps until the toolhead sensor (max `auto_load_max` 650), then back `park_dist` (70), selector back to neutral. Skipped while printing or when the toolhead sensor already has filament
- tool_stn measured 2026-10-24 (220 C, lane + extruder pushed together in 5/10 mm steps): filament out of the nozzle between 45 and 55 mm past the toolhead sensor, `tool_stn: 50`
- tool_stn: stock has none; after the sensor trip the IFS stops (F112) and the first flush is `G1 E90` with the IFS pushing (`F10 C<chn> ..`), so stock purges 90 mm from the sensor. Sensor-to-nozzle still to measure (hot)
- AFC lane move speeds set to stock feed speed (F1200 = 20 mm/s), AFC defaults were 50 / 150 mm/s
- `AFC_IFS` parks the selector at `neutral_angle` (45 deg) after homing when idle, otherwise lane 1 stays clamped
- Result: `AFC_HOME_UNIT UNIT=IFS_1` works, AFC.log `Homed lane IFS_Selector to ENDSTOP=IFS_1_home trigger after 90.022mm (steps=4097 dt=1.569s)`; `QUERY_ENDSTOPS` shows `IFS_1_home:TRIGGERED` at home
- `AFC.cfg` line 2 `VarFile: /usr/data/config/kalico/AFC/AFC.var` (upstream default `../printer_data/config/AFC/AFC.var`; backup `AFC.cfg.orig`). `AFC.var.unit not found` on the first start is normal, AFC creates it on the first save
- Open: AFC_Macro_Vars.cfg positions (cut, park, purge, kick, brush) are upstream placeholders; the stock AD5X change sequence is in `firmwareExe`, not in `printer.base.cfg`

## Plan notes

- Keep FlashForge's bootloader, flash Kalico at `0x08010000` with stock `IFSCommand`
- Clock: kalico-ad5x N32G45x is fixed at 128 MHz and its F1 `clock_setup()` gives 120 MHz with the 12 MHz crystal; needs the 144 MHz clock patch (see `../mainboard/NOTES.md`, "Clock")
- Kalico needs a board patch: on bootloader request, erase page `0x0800D000` + system reset (same as F37), so re-flashing over ttyS4 keeps working
- Host link is RS485 (AD5X has an RS485 converter on ttyS4, IFS has a transceiver, 4-pin Microfit 3.0 cable, source: github.com/ninjamida/ifs-jacker README)
- Kalico `src/stm32` has no RS485 direction control: needs a second patch to drive PA11 low while transmitting, high otherwise
- IFS Jacker (ninjamida) is an RP2040 MicroPython splitter for 2+ IFS units, speaks the stock F-protocol plus Z-commands; not a firmware replacement

## Open

- What PB5, PB6 do (likely OK/ERR LEDs D4/D5)
- Which motor connector (J8 "A" / J7 "B") is feed vs selector
- Driver chip marking (MS35776?) and Kalico tmc2209 compatibility
- Whether the R500 resistors are the sense resistors

## Purge chute moves (2026-10-24)

- Stock enters and leaves the chute along Y only: `printClearGoPos` / `clear_go_pos` = `G1 X52.5`, `G1 Y220 F12000`, `G1 Y229/230.5` (F3000 in clear_go_pos); `clear_brush` = `G1 Y220 F3000`, `G1 X78 F12000`, `G1 Y230.5`, X65/X73/X65/X73/X65, `G1 X78`, `G1 Y220`. AFC's Park/Poop/Brush macros move diagonally in one `G1 X.. Y..` (no approach option) and can catch the chute walls
- In `AFC_IFS.py`: `ADX_PARK`, `ADX_POOP` (park, then `AFC_POOP` with the same parameters), `ADX_BRUSH` (stock wipe, ends at Y220 out of the chute). Options with stock defaults: `chute_x` 52.5, `chute_y` 230.5, `chute_y_out` 220, `brush_x_min` 65, `brush_x_max` 73, `brush_x_out` 78, `brush_count` 2. At connect the unit sets AFC's `park_cmd` / `poop_cmd` / `wipe_cmd` to these, only where AFC.cfg still has the AFC defaults; AFC.cfg stays upstream
- AFC order: unload = cut, park; load = poop, wipe (kick off), wipe
- Checked against AFC: no built-in chute approach, no analog toolhead sensor (ADC only for the FPS buffer), `direct_load` loads to the nozzle on insert (stock parks), HTLF assumes home = no lane pressed (IFS home = slot 1)
- Selector speed 140 deg/s accel 400 (2026-10-24): A/B listening test, 90 deg/s was rough/loud (resonance), 140 = stock's TIM6 step rate sounded like stock
- Stock selector drive verified from the binary (2026-10-24): TIM6 = 144MHz/72/156 = 12820 Hz ISR, STEP toggled per tick = 6410 usteps/s = constant 140.86 deg/s, no acceleration anywhere (ARR never changes). Both TMC drivers get the same init (irun 9, ihold 0). Feed = TIM5 2 kHz planner tick, step DDA called N times per tick (N at 0x200002a8, default 1)
- selector_movement_accel 4000 (was 400): Klipper ramps sweep the loud ~90 deg/s band twice per move, stock jumps past it; 4000 = ~35 ms to 140 deg/s. ihold left at Kalico default (= run current) for now, stock uses ihold 0
- Prep without sweeps (2026-10-24): `AFC_IFS.system_Test` homes once per startup then does sensor-only lane checks (skips `AFC_HTLF.system_Test`, which re-homes the selector after every lane); matches stock = one homing at power-on
- hold_current 0.01 on both IFS motors (2026-10-24): stock IHOLD=0; Kalico's default hold=run snapped the rotor at every enable/disable = the loud click at the start/end of each select
- Clone TMC current scaling found 2026-10-24: in vsense=1 the clones deliver far less than spec. Kalico encoded 0.138 A as vsense=1/CS17 -> selector clicked over every cam lobe (weak), feed skipped at 20 mm/s. Stock's vsense=0/IRUN 9 (same nominal current) is clean - A/B'd live with SET_TMC_FIELD, user: "perfect". Fix: Kalico's 2209 current helper never drops to vsense=0 (it clamps at CS31 in vsense=1), so the delayed_gcode sets vsense=0 AND irun=9 on both motors + [delayed_gcode ifs_stock_current] trims both to stock IRUN 9 after startup. AFC only rewrites currents when print_current is set (we don't)
- Two-stage homing (2026-10-24): fast seek 140, back off `home_touch_backoff` (30 deg), re-approach at `home_touch_speed` (25 deg/s); homing dead-stops at trigger, and at 140 that slam through the gear backlash was the remaining click candidate
- Slow slot landings (2026-10-24): stopping on a slot at speed snapped the cam follower (clicked on every slot, empty or loaded; neutral landings quiet). `AFC_IFS.select_lane` now does the last `slot_land_dist` (15 deg) at `slot_land_speed` (20 deg/s); homing already lands the switch slot gently via the two-stage touch. A/B with fast 75 + slow 15 landings: user 'way better'
- Still clicked after that: the homing seek ends on slot 1 (home switch) at 140 deg/s, and AFC_HTLF re-homes before every select. Now homes once (seek at `home_speed` 45 deg/s, then the slow touch), tracks `selector_pos` and moves slot to slot / to neutral from there with the slow landing. Re-homes only after a homing failure
- Slow speeds (45 seek, 25 touch, 20 landing) strained audibly, so back to stock 140 deg/s everywhere, single homing move, no slow touch or landing; home-once position tracking kept. FORCE_MOVE neutral -> slot 2 at 140: no click with the motor off on arrival (stock) or left on 5 s, so enable state is not the cause
- Startup home at 140 still clicks. Normal FORCE_MOVE onto slot 1 (lane 1 loaded, home switch) also clicks, slot 2 (empty) quiet, slot 3 (empty) not judged. Open: loaded-lane clamp vs slot 1 itself; parked here for now

## No extrusion: IFS feed synced to the extruder (2026-10-24)

- First Benchy: nothing out of the nozzle. Extruder config, TMC registers, gear ratio, eboard firmware (144 MHz, STEPPER_BOTH_EDGE) all match stock; steps reach the driver (MSCNT moved 576 for E0.05, 584 expected)
- Cause: AFC `handle_activate_extruder` (and prep, load, unload) enables the lane drive and `sync_to_extruder`s it. IFS_Drive at stock IRUN 9 / IHOLD 0 (freewheel 0 = coils shorted at standstill) held the clamped lane back and the extruder slipped. With IFS_Drive disabled, E30 and E100 came out fine
- Stock keeps the feed motor off (EN high) while printing, the extruder pulls through the clamped lane
- `AFC_IFS.handle_connect`: the drive stepper's `sync_to_extruder` now disables the motor instead (AFC has no option for this). Feed moves (`lane.move`) still enable it as before

## Command names with digits never dispatch (2026-10-25)

- First T1 (lane 1 -> lane 2) failed at the unload: the console showed `Unknown command:"AD5"` twice where AFC called the cut and park, so the head never moved to the cutter and the retracts pulled an uncut strand
- Klipper's G-code parser (`gcode.py` `args_r = ([A-Z_]+|[A-Z*])`) takes the command as the first letter run plus the digits after it, so `AD5X_CUT` is read as `AD5`. The commands were registered (visible in HELP) but could not be invoked by name. Macro and command names must be letters and underscores only
- Renamed `AD5X_PARK/POOP/BRUSH/CUT` to `ADX_PARK/POOP/BRUSH/CUT` (AFC_IFS.py, registered at connect and swapped into AFC's park/poop/wipe/tool_cut command settings)
- Not caught earlier because the commands had never run by name since the rename from `IFS_*`; the old names worked

## Unload copies stock; AFC is only the framework (2026-10-25)

- Second T1 (after the ADX_ rename): cut and park ran, but the fill sensor stayed blocked through AFC's four 60 mm extruder retracts. Pulling the lane 1 filament out by hand cleared the sensor (0.007 -> 0.317), so the sensor sits on the lane side of the cutter and only the IFS retracting the lane clears it. The cut worked (confirmed by hand)
- Stock unload, read from the binary with Ghidra (string literals in instruction order, `scratchpad re-out`): `cutFilament` = `fourInOneCut`, `G92 E0`, then `F11 C<lane> L60 S<n>` sent to the IFS FIRST and `G1 E-60 F<n>` straight after (they overlap). `<n>` is `getFilamentTypeUnloadSpeed`: 600 mm/min for PLA and ordinary types, 200 or 300 for two special types and SILK; the distance is `getFilamentTypeUnloadSpace`, a constant 60
- Then `checkFourInOneUnLoad` -> `fourInOneUnLoad` (a state machine polling the IFS with F13 every 200 ms): when the IFS is idle it re-clamps the lane (`checkCrotchCutting`, F24) and sends `F11 C<lane> L70 S600`, and while `checkFilamentSenser` still reads filament it sends `F11 C<lane> L70 S600` again, until the IFS reports done or 'Unload timeOut!'. It never retries with the extruder. Other `F11` strings in the binary: `L50 S` in `doLoadAndUnload`; feeds use `F10 ... L1000 S`
- The global `UnloadESpace` 60 / `UnloadIFSSpace` 70 / `UnloadSpeed` 600 in Adventurer5M.json are only read by `initMulticolourConfig` and the `FourToOne::*DelayTime` estimators, not used as command lengths
- Total lane retract in stock = 60 + 70 (+70 per retry) at 600 mm/min = 10 mm/s
- AFC does the opposite (extruder retries up to `tool_max_unload_attempts`, then its own blind `dist_hub` lane retract), and the lane-to-extruder sync stays off because the idle IFS motor braked the strand
- `AFC_IFS._stock_unload`, run at the end of `ADX_CUT` (written with the stock numbers above, NOT run yet): chute park, lane back 60 mm at 10 mm/s, extruder back 60 mm at 10 mm/s, lane back 70 mm, then lane back 70 mm again (max `unload_ifs_retries` 3) while the sensor reads filament. AFC's own later lane retract is skipped once per unload (`_skip_hub_retract`, cleared by the `TOOL_UNLOAD` wrapper), and `tool_max_unload_attempts: 0` so AFC raises its error instead of retracting the extruder again
- Lane and extruder retracts run back to back, not at the same instant: `AFC_stepper._move(sync=False)` can drop the move when the motion queue wipes its trapq, and after the cut the two pieces are independent anyway
