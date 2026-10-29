# Stock IFS firmware

What the stock IFS firmware (version 3.0.7) does, decoded with Ghidra 12.2 in headless mode.

## Input

- `ifs.bin` from the control package (`main-update/control-extracted/ifs.bin`), 41168 bytes, sha256 `378af71ac647e5865f70e096193acdb19642860a3408457e3b2a44cf01e1c01f`
- The F19 reply is `four color. version: 3.0.7`
- `ifs.hex` in the older factory package (`factory-full/usr/prog/PROGRAM/control/1.0.6/`) is a different, older build
- Loaded raw: `-loader BinaryLoader -loader-baseAddr 0x08010000 -processor ARM:LE:32:Cortex`. The decompile has 243 functions.

## Memory layout

- The app is at `0x08010000`, size `0xA0D0`
- The bootloader is at `0x08000000` to `0x0800FFFF` and is not in the file
- Initial SP `0x20007498`, so at least 30 KB of RAM
- The flag page is `0x0800D000`, inside the bootloader area

## Bootloader entry: F37

The command parser (`FUN_08012de8`) parses `F<n>` and jumps through a table, with index n - 10. F37 does two things:

1. Unlocks the flash, clears the status, erases page `0x0800D000`, programs the word `0xFFFFFFFF` and locks it.
2. Sets FAULTMASK and writes `SCB->AIRCR = 0x05FA0004 | (AIRCR & 0x700)` (a system reset).

The app thus wipes its "app valid" flag and resets, and the bootloader then waits for `IFSCommand`. The stock `run.sh` does `ifsF37 /dev/ttyS4` and then `IFSCommand ifs.hex /dev/ttyS4`. Any replacement firmware has to do F37 the same way, or reflashing over `ttyS4` is lost (only SWD would remain).

## Host protocol (`ttyS4`, 115200 8N1, text)

- A command plus `\r\n`, then wait about 0.2 s, send `0xFF`, and read one reply line. The IFS never talks unasked: every reply comes from the F-command parser.
- **F13 status:** `FFS_state: %d silk_state: %d chan: %d ffs_channels_insert: %d stall_state: %d jinsi_GCONF: ... qiehuan_GCONF: ...`. It first reads GCONF from both TMCs. `FFS_state` is the selector state machine (5 = ready), `silk_state` has one bit per lane, and `stall_state` comes from the speed sensors.
- **Motion:** F10 feed, F11 exit (unload), F23 and F24 select the channel, F39 release, F112 stop both motors (PA5 and PB1 high).
- **Other:** F12 sensors, F14 and F40 stall, F19 version, F22 insert, F30. F41 to F64 read TMC registers (GCONF, GSTAT, DRV_STATUS, CHOPCONF, PWMCONF). `F42 S<1|2> I<0-31>` sets IRUN live on driver 1 or 2.
- F10 and F11 take `L` (length in mm), `S` (speed in mm/min) and `C` (channel). The IFS only moves `L` at `S` and stops, and the host decides everything else.

## Selector

- Bit-banged: one step is STEP high then low. The count goes up or down by one per step.
- Forward (count up) is DIR high, with GCONF `shaft=1`.
- EN is low while moving and high on arrival. The motor is off when parked (IHOLD is 0 too), and held by the mechanism.
- Speed: a timer interrupt (1 MHz divided by 156, 6410 Hz) toggles STEP, so 3205 microsteps per second, which is a constant 70.43°/s. There is no ramp anywhere.
- **Homing:**
    1. If the home sensor is already triggered, back off (DIR low) for up to 4096 steps until it clears. Error `0x7e` if it does not.
    2. Go forward for up to 16384 steps until the sensor triggers. Error `0x7e` if it is not found.
    3. The count is 0 at the sensor.
- **Positions**, in steps from home at 8 microsteps:

| Target | Position | Meaning |
|---|---|---|
| 1 | 0 | slot 1 (at the home sensor) |
| - | 2048 | neutral |
| 2 | 4096 | slot 2 |
| - | 6144 | neutral |
| 3 | 8192 | slot 3 |
| - | 10240 | neutral |
| 4 | 12288 | slot 4 |
| - | 14336 | neutral |

16384 steps is one full turn, so slots are every 90° and the neutral positions are halfway (45°) between them. 16384 microsteps at 8 microsteps is 2048 full steps per turn (geared).

## Feed motor

- The motion code is a generic 5-axis planner (five motors, all five table entries on PA0, PA1 and PA5), with one feed stepper wired. A 2 kHz planner tick calls the step routine N times per tick.
- Steps per mm come from a value in RAM (`343696245 / 1e6`): **343.696 steps/mm at 8 microsteps**.
- Stock keeps the feed motor off (EN high) while printing. The extruder pulls the filament through the clamped lane.

## TMC driver setup

The same for both drivers. Each driver has its own UART, with separate TX and RX pins, at 9600 baud. Writes are TMC2209 datagrams: sync `0x05`, slave address 0, `reg | 0x80`, 4 bytes, CRC8.

| Register | Value | Decoded |
|---|---|---|
| GCONF `0x00` | `0x1dc` | `en_spreadcycle=1`, `shaft=1`, `index_otpw=1`, `pdn_disable=1`, `mstep_reg_select=1`, `multistep_filt=1`, `I_scale_analog=0` |
| IHOLD_IRUN `0x10` | `0xa0900` | IHOLD=0, IRUN=9, IHOLDDELAY=10 |
| TPOWERDOWN `0x11` | `0x80` | 128 |
| CHOPCONF `0x6c` | `0x150082c3` | TOFF=3, HSTRT=4, HEND=5, TBL=1, `vsense=0`, MRES=5 (8 microsteps), `intpol=1` |
| PWMCONF `0x70` | `0xc80d174b` | stealthChop settings, unused because spreadCycle is on |

With the R500 (0.5 ohm) sense resistors, IRUN=9 would be about 0.14 A rms if the chip matches a TMC2209.

## Stock load and unload

- **Load:** `F10 C<chn> L650 S1200` until the toolhead sensor (first-load limit 650 mm, 20 mm/s). Tool changes use `L1000`.
- **Unload (`cutFilament`):** `fourInOneCut`, `G92 E0`, then `F11 C<lane> L60 S<n>` is sent to the IFS first and `G1 E-60 F<n>` straight after, so they overlap. `<n>` is 600 mm/min for PLA and ordinary types, 200 or 300 for two special types, and SILK.
- `checkFourInOneUnLoad` then polls the IFS with F13 every 200 ms. When it is idle, the host re-clamps the lane (F24) and sends `F11 C<lane> L70 S600`, and while the toolhead sensor still reads filament it sends the same again, until the IFS reports done or "Unload timeOut!". It never retries with the extruder.
- `UnloadESpace` (60), `UnloadIFSSpace` (70) and `UnloadSpeed` (600) in `Adventurer5M.json` are only read by the config initialisation and the delay estimators, not used as command lengths.
- The total lane retract is 60 + 70 (+70 per retry) at 10 mm/s.
- The four tubes stay separate up to the 4-in-1 at the toolhead, so a parked lane sits about 70 mm back.

## Stock purge chute moves

Stock enters and leaves the chute along Y only. `printClearGoPos` and `clear_go_pos` are `G1 X52.5`, `G1 Y220 F12000`, `G1 Y229` or `Y230.5` (F3000 in `clear_go_pos`). `clear_brush` is `G1 Y220 F3000`, `G1 X78 F12000`, `G1 Y230.5`, then X65, X73, X65, X73, X65, then `G1 X78` and `G1 Y220`.

More decoded flows are on the other IFS pages: [stock host flows](STOCK_SPEC_HOST.md), [IFS side](STOCK_SPEC_IFS.md) and [load wizard](STOCK_LOAD_WIZARD.md).
