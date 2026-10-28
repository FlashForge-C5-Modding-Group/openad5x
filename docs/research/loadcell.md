# AD5X bed / load cell notes

Goal: know how the bed probe works without FlashForge's `firmwareExe`, so Kalico can level and probe.

## Hardware (spare part photo, West3D SKU ELE4358 "Flashforge AD5X Pressure leveling sensor (Strain Gauge)")

- 4 strain-gauge load cells (U-cut plates), labels `739 H`, `734 X`, `736 X`, `730 H` (two matched pairs?), 3-wire (half bridges)
- Small board: square QFN chip (likely the MCU with the H-command firmware), 8-pin chip (likely the 24-bit ADC, e.g. CS1237 / HX71x type, marking not readable), white 5-pin connector to the mainboard (power, GND, UART ttyS7, trigger to PB3?), white rectangular part
- No firmware for this board in FlashForge's packages, no update code in firmwareExe (only H1 / H7 / H2 / H3)
- FlashForge wiki photo (`wiki.flashforge.com/resource/pictures/ad5x_picture/ad5x_introduction/电子秤.png`, "electronic scale", 800x400): board silkscreen **"GUAGE-SENSOR"**
  - **J9 "ISP": VCC RX TX GND**: UART programming header (MCU with a UART ROM bootloader, e.g. STC / Puya PY32 / WCH type)
  - **U4**: 16-pin SOP, **HX711** (confirmed by the user 2026-10-23): DOUT pin 12, PD_SCK pin 11; Kalico supports it (`[load_cell]` / `[load_cell_probe]`, `sensor_type: hx711`)
  - **U7**: **STC8G1K08A** (SOP-8, marking `STC 8G1K08A A557138 2552XB`, close-up by the user 2026-10-23, `Downloads\20261023_142003.jpg`): 8051 core, 8 KB flash; pins P5.4/RST, VCC, P5.5, GND, P3.0 RxD, P3.1 TxD, P3.2, P3.3; STC UART ISP in ROM listens on P3.0/P3.1 for `0x7F` at every power-on (J9 "ISP"); STC ISP has no flash read, so the stock firmware can't be dumped; no Klipper / Kalico support for 8051
  - **K2**: button (reset / tare?)
  - J6 / J8 / J3 / J7 = load cells A / B / C / D (`E+ E- ...`), J1 5-pin to the mainboard
  - Chip markings not readable in the photo
- If U4 is an HX711: Kalico has `load_cell` / `load_cell_probe` with `hx71x`. Kalico could read it directly (tare part of the probe, no H commands) if U7 ran Kalico (unlikely for an 8-pin 8051 / PY32 / CH32V0) or if HX711 DOUT / SCK were wired to free pins on a Kalico MCU (hardware mod)
- Mainboard side: **J23 "LEVEL"**, 6 pins `VCC RX TX RES DET GND` (wiki photo `ad5x_introduction/pic13.png`, mainboard `FFP0302_Main_Board_V3.0.0`); board side J1 6-pin
  - RX / TX: the STC UART, to the SoC ttyS7
  - DET: trigger, to the mainboard N32 PB3 (`[probe]`)
  - RES: reset line to the STC. firmwareExe never drives it (its GPIO helpers `gpio_out` / `gpio_export` / `gpio_set_value` are only used by `MainWindow::doPowerOff`, `Print::printCompletedPowerOff`, `sLightCheck`); not in the stock Klipper config either. So it ends at an unused N32 pin, an unused SoC GPIO, or nowhere (pulled up). Needs a multimeter / trace check
  - A pure electrical passthrough over J23 needs two N32 pins to STC GPIOs; only DET is one (RES only resets the STC)
- **Stock mainboard firmware drives PC0 itself** (`../mainboard/re/mainboard_v.c`):
  - `FUN_08004640`, called from the main init `FUN_080068c8` (before the Klipper scheduler): GPIOC clock on, `GPIO_Init(GPIOC, PC0, push-pull out, 50 MHz)`, PC0 high
  - `FUN_08004674`: sets / clears PC0 from counters (`0x2000017c`, `0x20000184`, `0x2000015c`, `0x20000158`): a pulse generator, fits the FlashForge MCU command `set_radar_sync_pulse oid pulse_cnt pulse_interval` (host side in FlashForge's `bus.py`, `i2c_set_software_bus ... radar_interval`)
  - PC0 is in no stock config section. Kalico doesn't set it (input now)
  - Was a candidate for J23 "RES" (STC reset or tare input); tested 2026-10-23: neither (see "Live tests")
  - Test idea: Kalico `[output_pin level_res] pin: PC0 value: 1`, H7 baseline with a light press, pulse PC0 low, H7 again (~0 = tare, no reply / restart = reset, no change = not J23)

## Live tests on ttyS7 (2026-10-23, Kalico host, `/tmp/h7.sh <cmd>`: stty 9600 raw, send cmd + `\n`, read 1.5 s)

- Kalico config: `[output_pin level_res] pin: PC0 value: 1 shutdown_value: 1` inserted before SAVE_CONFIG in `/usr/data/config/kalico/printer.cfg` (backup `printer.cfg.before-pc0`), RESTART, ready
- Real replies on our board:
  - `H7` -> `command H7 ok. 8840174 -520 g`, `command H7 ok. 8840104 -520 g` (untared, nothing on the bed)
  - `H1` -> `command H1 ok. 8839484` (raw count only)
  - after `H1`: `H7` -> `command H7 ok. 8839237 0 g`, `... 8839459 0 g`: **H1 tares** (confirmed on hardware)
- PC0 low 100 ms (`SET_PIN PIN=level_res VALUE=0`, `G4 P100`, `VALUE=1`):
  - before any tare: -520 g -> -540 g (raw 8840104 -> 8839739), board answered normally: not a tare
  - after `H1`: still 0 g (raw 8839347 / 8839463): tare not lost, so PC0 most likely doesn't reset the STC (unless the tare is kept in STC EEPROM)
- Raw noise: a few hundred counts between reads (~0.5 g steps)
- **PC0 held low (~3 s), `H7` during it**: `command H7 ok. 8839437 0 g`, after release `... 8839192 0 g`: the STC keeps running with PC0 low, so **PC0 is not J23 RES / not the STC reset**. PC0 (stock "radar sync pulse" output) goes somewhere else
- `[output_pin level_res]` on PC0 still in the Kalico config (value 1, as stock drives it at boot)
- J23 RES destination still unknown (another N32 pin, an SoC GPIO, or not driven): needs a continuity check
  - If RES can be driven from the printer: STC ISP flashing over ttyS7 without an adapter (reset + `0x7F`, `stcgal`)
- Routes without a host helper:
  1. bypass the STC: HX711 DOUT / PD_SCK to two free pins on a Kalico MCU, Kalico `[load_cell_probe]` `sensor_type: hx711` (tare, trigger, calibration in Kalico); STC held in reset or disconnected from those lines; hardware mod
  2. own STC8G firmware (SDCC, STC ISP over J9): possible, but still a serial protocol, not Kalico
- Needed for route 1: HX711 pin 12 (DOUT) / pin 11 (PD_SCK) -> which STC pins, J1 pinout and where J1 lands on the mainboard, two free Kalico MCU pins

## Config (stock = Kalico copy)

- `[probe] pin: !PB3` (mainboard), `z_offset: -0.25`, `samples: 3`, `samples_result: average`, `speed: 5`, `samples_tolerance: 0.1`, `samples_tolerance_retries: 4`
- `[bed_mesh]` 5x5, 0-215 mm, bicubic
- `[stepper_z] endstop_pin: PD2`
- `[heater_bed]` PB9 / PA0 Generic 3950, PID, `max_power: 0.4`

## firmwareExe (software 3.1.6) strings

- Levelling uses plain Klipper commands: `G28 Z`, `BED_MESH_CALIBRATE`, `PROBE_CALIBRATE`, `SET_GCODE_OFFSET Z=`, `BED_MESH_PROFILE SAVE=MESH_DATA` / `LOAD=MESH_DATA`, `SAVE_CONFIG`
- Load cell calibration screen `WeightAdjust` (`../ad5x/dialog/weightAdjust.cpp`): `G1 Z100 F2000`, `M140 S60`, buttons `H1 Point`, `H2-S500`, `H3-S200`, `H3-S100`, `getWeightValue()`, `Weight:`, `T:60/60`; commands sent `H2 S500`, `H3 S200`, `H3 S100` (H1 probably zero / tare, H2 S500 calibrate with 500 g, H3 S200 / S100 check). Not Klipper commands (FlashForge's klippy has none), so sent to a board over serial
- Errors: "Level probe can not clear.", "Leveling sensor data cannot be cleared.", "Level probe no trigger.", "Leveling sensor not triggered.", "Leveling sensor triggered early.", "Abnormal leveling data"
- `/dev/ttyS7` in `../ad5x/serial/SerialObject.cpp` next to "clientApi", "close serial device", "parse register response data error", "length = 400"; `/dev/ttyS3` "Serial: serial /dev/ttyS3 open fail"

## Live printer (2026-10-23, Kalico host, read-only)

- UARTs: ttyS0 console, ttyS2 mainboard, ttyS3, ttyS4 IFS, ttyS5 eboard, ttyS7 (`uart7`, MMIO `0x10037000`)
- ttyS3 / ttyS7 not opened since boot, no process holds them
- Listening on ttyS7 4 s each at 115200 / 230400 / 9600: 0 bytes (nothing unsolicited)
- `QUERY_PROBE` under Kalico: not triggered (`last_query: 0`)
- `/usr/prog/config/Adventurer5M.json`: `zLevelOffset: -3.2341663837432861`, `zProbeOffset: 0.039999999105930328`, `zOffset: 0.0` (firmwareExe keeps its own Z offsets; Kalico only has `z_offset: -0.25`)
- No `/usr/data/config/levelPrint.cfg`

## First hardware test under Kalico (2026-10-23 ~18:12, done by hand)

From `/usr/data/logs/klippy.log`:
- TMC2209 UART works: `TMC 'stepper_x' / 'stepper_y' / 'stepper_z' reports GSTAT: 00000001 reset=1(Reset)` on enable, then `00000000`
- Homing X, Y, Z ran (`homing: needs rehome`, `needs_home_current_change` lines), no errors
- `QUERY_PROBE` three times: `probe: open`, `probe: open`, `probe: TRIGGERED`: the load cell board drives PB3 by itself, no tare / command from firmwareExe needed for a trigger
- No errors, shutdowns or protocol problems in the log; Kalico telemetry notice only (`DISABLE_TELEMETRY` to opt out)

## Protocol (Ghidra decompile of firmwareExe 3.1.6: `refs.c`, `uart7.c`, `level.c`, `send.c`)

- Port: **`/dev/ttyS7`, 9600 baud** (`SerialObject::getInstance` -> `serialOpen("/dev/ttyS7")` -> `Serial::open()`, `cfsetispeed/cfsetospeed(0xd)` = B9600)
- `Serial("/dev/ttyS7", "~", "\n")`: `Serial::send` writes `"%s%s"` = command + `"\n"`, plain text; `~` probably ends a reply (`Serial::recvFromUart7`)
- `SerialObject::sendCmdToUart7(cmd)`: tcflush, send, read reply with `recvFromUart7`, up to 5 tries
- Commands:
  - `H1`: zero / tare (also the `H1 Point` button in `WeightAdjust`)
  - `H7`: read value; reply split at spaces, field 4 = value (int)
  - `H2 S500`: calibrate with 500 g (`WeightAdjust`, bed at 60 C, Z 100)
  - `H3 S200`, `H3 S100`: check with 200 g / 100 g
- **`SerialObject::checkLevelPinStatus()`** (`level.c`): up to 10 times: send `H1`, send `H7`, take field 4; ok when |value| < 31 (`0x1f`), returns 1; after 10 fails returns 0 ("Level probe can not clear")
- Called from: `Print::doPreparation` (before every print), `Print::checkZ`, `GuiderLevelPrint::doLevel`, `Settings::doLevel`, `WeightAdjust::on_H1_clicked`
- So stock tares the load cell before every print, Z check and levelling, then the probe itself is plain Klipper `[probe]` on PB3
- (ttyS4 IFS: `Serial::openUart4()` opens `/dev/ttyS4` at `0x1002` = B115200)

## kiln-os (djvalic/kiln-os, GPLv3): same findings, plus hardware tests

Source: `docs/bed-weighing-board.md` (stock app run in a qemu sandbox + one read on a real AD5X), `klipper/extras/ad5x_weight.py`, `klipper/ad5x.cfg`.
- Reply complete when > 12 bytes and contains `ok`; stock waits up to 1 s for more bytes, 5 send attempts
- **Real board reply** (their unit, 2026-10-15): `H7` -> `command H7 ok. 8596371 60 g \r\n`: field 4 = raw ADC count, **field 5 (index 4 after split) = grams**, here 60 g untared; three reads within 1 raw count; nothing sent unasked
- Sandbox replies (not real): `H1 ok. tare done`, `H7 ok. weight value: <n>`
- Tare failure: stock cancels the print (mesh dropped, heaters / fan / motors off), "Leveling sensor cannot be cleared. Please check the sensor."; with no board answering the reading parses as 0 and the check passes
- Tare runs right before each `PROBE_CALIBRATE` (used to measure Z) and before `BED_MESH_CALIBRATE`
- Stock `checkZ` before every print: home Z (max endstop), X, Y; purge box, heat, purge 90 mm, wipe; Z5, X60 Y-3, tare, `PROBE_CALIBRATE` + `ABORT` (z1); scrub front edge (z1+0.3, X130-X150, z1+0.1); bed centre X107.5 Y107.5, tare, probe (z2); diff = z2 - saved centre Z, `SET_GCODE_OFFSET Z=<diff> MOVE=1` if -0.5..2.0; `BED_MESH_PROFILE LOAD=MESH_DATA`; then at print start `SET_GCODE_OFFSET Z=<zProbeOffset> MOVE=1` (absolute, replaces the drift offset): the `zProbeOffset` from `/usr/prog/config/Adventurer5M.json` (0.04 on our printer)
- "Level before print": steps 2-3, then `BED_MESH_CALIBRATE` (own tare), `BED_MESH_OUTPUT`, `BED_MESH_PROFILE LOAD=default`
- `ad5x_weight.py`: `[ad5x_weight]` (`serial`, `baud`, `reply_timeout`, `send_attempts`, `tare_attempts`, `tare_tolerance`), commands `WEIGHT_TARE`, `WEIGHT_READ`, `WEIGHT_SEND CMD=H...` (H commands only), status `connected` / `weight`
- `ad5x.cfg`: `[ad5x_weight] serial: /dev/ttyS7 baud: 9600`, macro `LOAD_CELL_TARE` -> `WEIGHT_TARE` (zMod's name), `BED_MESH_CALIBRATE` wrapper with `WEIGHT_TARE` before `_BED_MESH_CALIBRATE_BASE`
- Not confirmed on hardware (per kiln-os): that `H1` really tares and the probe triggers on contact after it; what `H2` / `H3` calibrate (don't send them)

## What Kalico needs

- Before homing Z / probing / a print: send `H1\n` to ttyS7 at 9600, check `H7` field 4 |value| < 31, retry up to 10 times, error if not
- Way: a small host module (ttyS7 serial, `LOAD_CELL_TARE`-style command) called from macros before `G28 Z` / `BED_MESH_CALIBRATE` / print start
- To check first, read-only: the exact reply format of `H1` / `H7` (one `H7` by hand on ttyS7)
- kiln-os has `klipper/extras/ad5x_weight.py` (AD5X, mainline Klipper): probably the same job, worth reading as reference

## Kalico load cell commands -> board H commands (installed 2026-10-23)

Kalico's own command names, as macros (there is no `[load_cell]` section, so the names are free), each sending the board's H command through Kalico's built-in `[gcode_shell_command]`:

| Kalico command | Board | Output |
|---|---|---|
| `LOAD_CELL_TARE` | `H1`, check `H7` \|g\| < 31, up to 10 times (as stock `checkLevelPinStatus`) | `load cell: tared, 0 g` / `tare failed, <g> g after 10 tries` |
| `LOAD_CELL_READ` | `H7` | `load cell: <g> g (raw <count>)` |
| `LOAD_CELL_DIAGNOSTIC [COUNT=10]` | `H7` x COUNT | `load cell: <n> reads, min <g> g, max <g> g, spread <g> g` |
| `LOAD_CELL_CALIBRATE` | not mapped (`H2` / `H3` unconfirmed, change the factory calibration) | |

Files (sources in this folder):
- `loadcell.sh` -> `/usr/data/kalico/loadcell.sh` (755): `send` = stty 9600 raw, command + `\n`, reply complete when > 12 bytes and contains `ok`, 1 s per try, 5 tries; `tare` / `read` / `diag [count]`
- `loadcell.cfg` -> `/usr/data/config/kalico/loadcell.cfg`: `[gcode_shell_command loadcell] command: sh /usr/data/kalico/loadcell.sh timeout: 60 verbose: True` + the three macros
- `kalico/printer.cfg`: `[include loadcell.cfg]` before the SAVE_CONFIG block (backup `printer.cfg.before-loadcell`)

Test after RESTART: `LOAD_CELL_READ` -> `0 g (raw 8839311)`, `LOAD_CELL_TARE` -> `tared, 0 g`, `LOAD_CELL_READ` -> `0 g (raw 8839488)`, `LOAD_CELL_DIAGNOSTIC COUNT=5` -> `min 0 g, max 0 g, spread 0 g`

Limits:
- `RUN_SHELL_COMMAND` ignores the exit code: a failed tare is only shown in the console, the macro goes on (stock cancels the print)
- Probe tests by the user (2026-10-23, Kalico):
  - `PROBE` with an old zero: sample 1 -2.695, then each sample ~0.15 mm after the 2 mm retract (+1.85 each), "Probe samples exceed samples_tolerance"
  - nozzle still on the bed after a `PROBE` (Klipper's `PROBE` doesn't lift after the last sample): `LOAD_CELL_READ` 460 g, next `PROBE` "Probe triggered prior to movement"
  - `LOAD_CELL_TARE` with the nozzle off the bed, then `PROBE`: -3.2425 / -3.2725 / -3.265, result -3.260 (spread 0.03 mm, 3 samples in one session fine)
- Stock sequence (`Settings::doLevel`, `Print::checkZ`, `GuiderLevelPrint::doLevel`, decompile `dolevel.c`): `G1 Z5 F800`, `G1 X60 Y-3` (or `X107.5 Y107.5`), `M400`, `checkLevelPinStatus` (H1 + H7; fail = `E0041`, `G1 Z100 F800`), `PROBE_CALIBRATE` (plain, `[probe]` defaults), `ABORT`, `G1 Z5` / `G1 Z100`; checks "No trigger", "Probe triggered prior to movement", "Endstop x/y/z still triggered"; the mesh gets the same single tare first. FlashForge's `probe.py` is plain upstream (no pause / tare between samples)
- So: tare with the nozzle off the bed, once per probe session (not per sample)
- `[probe] activate_gcode` doesn't fit: Kalico errors when the toolhead moves in it ("Toolhead moved during probe activate_gcode script"), so it can't lift to Z5
- Wrappers (2026-10-23, `loadcell.cfg` md5 `8c8234ebd95de341458e9708ffbfe23f`): `_LOAD_CELL_PREPARE` = `SAVE_GCODE_STATE`, `G90`, `G1 Z5 F800`, `RESTORE_GCODE_STATE`, `M400`, `LOAD_CELL_TARE`; `PROBE`, `PROBE_ACCURACY`, `PROBE_CALIBRATE`, `BED_MESH_CALIBRATE` with `rename_existing` (`_PROBE_BASE`, `_PROBE_ACCURACY_BASE`, `_PROBE_CALIBRATE_BASE`, `_BED_MESH_CALIBRATE_BASE`): `_LOAD_CELL_PREPARE`, then the original with `{rawparams}`. Not on `G28 Z` (Z homes to its endstop PD2). After RESTART: ready, all macros and renamed builtins listed
- Test with the wrappers (user, 2026-10-23 16:36): `PROBE` twice in a row at X110 Y110, each `load cell: tared, 0 g` first: -3.2325 / -3.285 / -3.275 = -3.264167, then -3.265 / -3.255 / -3.245 = -3.255; spread ~0.05 mm per probe, 0.009 mm between the two results. Works

## Z homing: switch, then bed probe = Z0 (installed 2026-10-23)

- Why: in switch coordinates (`[stepper_z] position_endstop: 220`) the nozzle touches the bed at Z ~ -3.26 (centre `PROBE` -3.255 / -3.264, stock mesh ~ -3.0, stock `zLevelOffset: -3.234` in `Adventurer5M.json`)
- Kalico `PROBE HOME=Z` (`probe.py` `cmd_PROBE`): sets toolhead Z = current Z - `last_z_result`, so the touch point becomes Z ~ 0; macros can also read `printer.probe.last_z_result`
- `ad5x_home.cfg` -> `/usr/data/config/kalico/ad5x_home.cfg`, `[include ad5x_home.cfg]` after `[include loadcell.cfg]` in `kalico/printer.cfg` (backup `printer.cfg.before-home`):
  - `[gcode_macro G28] rename_existing: G28.1`: `G28.1 {rawparams}`, then `_HOME_Z_PROBE` if no axes given or Z included
  - `_HOME_Z_PROBE` (only if X and Y are homed, else a console note): `SAVE_GCODE_STATE`, `G90`, `G1 Z10 F1500`, `G1 X107.5 Y107.5 F12000`, `PROBE HOME=Z` (wrapper: Z5, M400, tare, 3 samples), `G1 Z5 F800`, `RESTORE_GCODE_STATE`
  - First try `rename_existing: _G28_BASE` -> "G-Code macro rename of different types ('G28' vs '_G28_BASE')": a traditional G-code can only be renamed to a traditional one, so `G28.1`
- Config limits unchanged (220 / 230 / -10): with the touch = 0 the switch is at ~223.3, so the axis may go ~6.7 mm past the switch (stock 10 mm)
- Stock `HOME` macro homes Z first (then X, Y): with it the bed probe is skipped (X / Y not homed yet); plain `G28` homes X, Y, Z
- After RESTART: ready, `G28` macro, `G28.1` renamed builtin, `_HOME_Z_PROBE` listed
- Test (user, 2026-10-23 17:00): `G28` -> tared, -3.2225 / -3.2675 / -3.255, `Result is z=-3.248333`; toolhead X107.5 Y107.5 Z5, `homing_origin` 0; then `PROBE` at the centre -> 0.018333 / -0.029167 / -0.021667, `Result is z=-0.010833`: the touch is Z ~ 0. Works
- Then needed: new `BED_MESH_CALIBRATE` (old `MESH_DATA` carries the -3), check `[probe] z_offset: -0.25` with a first layer

## Ghidra

- `scripts/run.sh` imports and analyses `firmwareExe` (copy in this folder) into `proj/`, then `scripts/DecompRefs.java` decompiles the functions that use given strings into `refs.c`
- `scripts/funcs.sh <out> <name part> ...` + `DecompFuncs.java`: decompiles functions by name and lists their callers (`uart7.c`, `level.c`, `send.c`)
- MIPS string pointers: `local_30 = &PTR_s_..._00af0000; (char*)(local_30 + -0x1a2a)` = `0x00af0000 - 0x1a2a*4` = `0x00ae9758` = "H1" (resolve vaddr -> file offset with the ELF program headers)

## Open

- `H1` reply on a real board, meaning of the `~`
- Whether the trigger point stays right without the `H1` tare (it triggers, but drift would show as bad z or bad mesh)
- `zLevelOffset` (-3.23): what stock uses it for (`zProbeOffset` = print-start `SET_GCODE_OFFSET`, see kiln-os)
- What ttyS3 is
- z_offset 0 (2026-10-24): probe touch = nozzle on the bed = Z0 with the probe-based G28, stock's -0.25 removed (backup printer.base.cfg.before-zoffset). Old saved meshes (MESH_DATA, auto) still carry the stock -3.2 frame and must not be loaded; mesh fresh at print start
