# Bed load cell

How the bed probe works without FlashForge's `firmwareExe`, so Kalico can level and probe. How Kalico uses it is on [Load cell in Kalico](loadcell-kalico.md).

## Hardware

The spare part is sold as "Flashforge AD5X Pressure leveling sensor (Strain Gauge)" (West3D SKU ELE4358).

- **Load cells:** 4 strain-gauge cells (U-cut plates), labelled `739 H`, `734 X`, `736 X` and `730 H`, 3-wire (half bridges). J6, J8, J3 and J7 are cells A, B, C and D.
- **Board:** silkscreen "GUAGE-SENSOR" (FlashForge wiki photo "electronic scale"):
    - **U4:** a 16-pin SOP **HX711**, with DOUT on pin 12 and PD_SCK on pin 11. Kalico supports it (`[load_cell]` and `[load_cell_probe]` with `sensor_type: hx711`).
    - **U7:** an **STC8G1K08A** (SOP-8, 8051 core, 8 KB flash). Its pins are P5.4/RST, VCC, P5.5, GND, P3.0 RxD, P3.1 TxD, P3.2 and P3.3.
    - **J9 "ISP":** VCC, RX, TX, GND. This is the STC's UART programming header: the ROM bootloader listens on P3.0 and P3.1 for `0x7F` at every power-on.
    - **K2:** a button (reset or tare).
    - **J1:** 5-pin, to the mainboard.
- **No firmware for this board** is in FlashForge's packages, and `firmwareExe` has no update code for it (only `H1`, `H7`, `H2` and `H3`). STC's ISP has no flash read, so the stock firmware cannot be dumped. There is no Klipper or Kalico support for an 8051.
- **Reading the HX711 directly** would let Kalico tare and probe without the H commands. It needs either Kalico running on the STC (unlikely for an 8051) or the HX711 DOUT and SCK wired to free pins on a Kalico MCU, which is a hardware mod.

### Mainboard side

**J23 "LEVEL"** is 6 pins: `VCC RX TX RES DET GND` (mainboard `FFP0302_Main_Board_V3.0.0`). The board side is J1, also 6-pin.

| Pin | Goes to |
|---|---|
| RX, TX | The STC's UART, to the SoC's `ttyS7` |
| DET | The trigger, to the mainboard N32 PB3 (`[probe]`) |
| RES | Reset line to the STC. `firmwareExe` never drives it, and it is not in the stock Klipper config. Where it ends is unknown (an unused N32 pin, an unused SoC GPIO, or nowhere). It needs a multimeter or trace check |

The stock mainboard firmware drives **PC0** itself. It sets PC0 high in its init, and a pulse generator then sets and clears it from counters, which fits the FlashForge MCU command `set_radar_sync_pulse`. PC0 is in no stock config section, and Kalico leaves it as an input. It looked like a candidate for RES, but tests showed it is not (below).

## What the board does

Tested on a real board, over `ttyS7` at 9600 baud, with a command plus `\n` and a 1.5 s read:

- `H7` replies `command H7 ok. 8840174 -520 g`: the raw count and then the weight in grams. A board that was not tared reads about -520 g with nothing on the bed.
- `H1` replies `command H1 ok. 8839484` (the raw count only). **`H1` tares**: a following `H7` reads `0 g`.
- Raw noise is a few hundred counts between reads, about 0.5 g.
- Nothing is sent unasked: listening for 4 s at 115200, 230400 and 9600 gave 0 bytes.
- **PC0 is not the STC reset.** Pulling PC0 low for 100 ms did not tare or reset the board (a tared 0 g stayed 0 g). Holding PC0 low for about 3 s and reading `H7` during it, the STC kept answering. PC0, the stock "radar sync pulse" output, goes somewhere else.
- `QUERY_PROBE` under Kalico reads "not triggered" with nothing on the bed. The board drives PB3 by itself, so no command is needed for a trigger.
- If RES can be driven from the printer, the STC could be flashed over `ttyS7` without an adapter (reset plus `0x7F`, `stcgal`).

## Protocol (from the `firmwareExe` 3.1.6 decompile)

- **Port:** `/dev/ttyS7`, 9600 baud (`cfsetispeed` and `cfsetospeed` with `0xd`, B9600). The IFS port, `ttyS4`, is opened at B115200.
- **Format:** `Serial("/dev/ttyS7", "~", "\n")`. A command is sent as the text plus `\n`. The `~` probably ends a reply.
- **`sendCmdToUart7`:** flush, send, read the reply, up to 5 tries. A reply is complete when it has more than 12 bytes and contains `ok`, and stock waits up to 1 s for more bytes.
- **Commands:**

| Command | What it does |
|---|---|
| `H1` | Zero (tare). Also the `H1 Point` button in the `WeightAdjust` screen |
| `H7` | Read the value. The reply is split at spaces: field 4 is the raw count, field 5 the grams |
| `H2 S500` | Calibrate with 500 g (`WeightAdjust`, bed at 60 °C, Z 100). It changes the factory calibration, so do not send it |
| `H3 S200`, `H3 S100` | Check with 200 g or 100 g. Not confirmed on hardware, do not send |

- **`SerialObject::checkLevelPinStatus()`:** up to 10 times, send `H1`, then `H7`, and take field 4. It succeeds when the absolute value is below 31 and fails after 10 tries ("Level probe can not clear").
- It is called from `Print::doPreparation` (before every print), `Print::checkZ`, `GuiderLevelPrint::doLevel`, `Settings::doLevel` and `WeightAdjust::on_H1_clicked`.

So stock tares the load cell before every print, Z check and levelling, and the probe itself is plain Klipper `[probe]` on PB3.

## Stock levelling

- **Commands:** plain Klipper ones: `G28 Z`, `BED_MESH_CALIBRATE`, `PROBE_CALIBRATE`, `SET_GCODE_OFFSET Z=`, `BED_MESH_PROFILE SAVE=MESH_DATA` and `LOAD=MESH_DATA`, `SAVE_CONFIG`.
- **Errors shown:** "Level probe can not clear.", "Leveling sensor data cannot be cleared.", "Level probe no trigger.", "Leveling sensor not triggered.", "Leveling sensor triggered early." and "Abnormal leveling data".
- **A failed tare** cancels the print: the mesh is dropped and the heaters, fan and motors are turned off, with "Leveling sensor cannot be cleared. Please check the sensor." If no board answers, the reading parses as 0 and the check passes.

### The check before every print (`Print::checkZ`)

1. Home Z (max endstop), X and Y. Purge box, heat, purge 90 mm, wipe.
2. `Z5`, `X60 Y-3`, tare, `PROBE_CALIBRATE` and `ABORT` (this gives z1).
3. Scrub the front edge (z1 + 0.3, X130 to X150, z1 + 0.1).
4. Bed centre `X107.5 Y107.5`, tare, probe (z2).
5. The difference is z2 minus the saved centre Z. `SET_GCODE_OFFSET Z=<diff> MOVE=1` is sent if it is between -0.5 and 2.0.
6. `BED_MESH_PROFILE LOAD=MESH_DATA`.

The "level before print" steps are the same up to step 3, then `BED_MESH_CALIBRATE` (with its own tare), `BED_MESH_OUTPUT` and `BED_MESH_PROFILE LOAD=default`.

### Stock Z values

`Adventurer5M.json` holds `zLevelOffset` -3.2342, `zProbeOffset` 0.04 and `zOffset` 0.0:

- `zLevelOffset` is read as the "level print point Z", used as the saved centre height when the check is configured that way.
- `zOffset` (the left extruder's Z offset) appears to be unused: nothing sends it to Klipper.
- `zProbeOffset` is the saved live Z adjustment from the print screen, saved as the screen's offset minus its adjustment. Its use at the start of a print was not traced in the decompile. The kiln-os notes say stock sends `SET_GCODE_OFFSET Z=<zProbeOffset> MOVE=1` at print start (absolute, replacing the drift offset).
- At the end of a print stock sends `SET_GCODE_OFFSET Z=0 MOVE=1` and `BED_MESH_CLEAR`.

## kiln-os findings

[kiln-os](https://github.com/djvalic/kiln-os) (GPLv3) has the same findings, from `docs/bed-weighing-board.md` (the stock app run in a QEMU sandbox, plus one read on a real AD5X), `klipper/extras/ad5x_weight.py` and `klipper/ad5x.cfg`:

- A real board answered `H7` with `command H7 ok. 8596371 60 g \r\n` (60 g untared, three reads within 1 raw count).
- The tare runs right before each `PROBE_CALIBRATE` and before `BED_MESH_CALIBRATE`.
- `ad5x_weight.py` provides `[ad5x_weight]` (`serial`, `baud`, `reply_timeout`, `send_attempts`, `tare_attempts`, `tare_tolerance`) and the commands `WEIGHT_TARE`, `WEIGHT_READ` and `WEIGHT_SEND CMD=H...`.
- Not confirmed on hardware by kiln-os: that `H1` really tares and the probe triggers on contact after it, and what `H2` and `H3` calibrate.

## Open

- The `H1` reply format on every board revision, and the meaning of the `~`.
- Whether the trigger point stays right without the `H1` tare. It triggers, but drift would show as a bad Z or a bad mesh.
- How stock applies `zProbeOffset` at the start of a print.
