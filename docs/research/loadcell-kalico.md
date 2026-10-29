# Load cell in Kalico

How Kalico probes and levels with the AD5X bed load cell. The board and its protocol are on [Bed load cell](loadcell.md).

The trigger is a plain `[probe]` on PB3, which the board drives itself. Kalico only has to tare the board before probing, with `H1` and `H7` on `ttyS7`. There is no `[load_cell]` section, so Kalico's own load cell command names are free and are used as macros.

## Commands

| Command | What it does |
|---|---|
| `LOAD_CELL_TARE` | `H1`, then `H7`; succeeds when the reading is below 31 g, up to 10 tries |
| `LOAD_CELL_READ` | `H7`: shows grams and the raw count |
| `LOAD_CELL_DIAGNOSTIC [COUNT=10]` | Reads `H7` several times and shows min, max and spread |
| `LOAD_CELL_CALIBRATE` | Not mapped (`H2` changes the factory calibration) |

## Files

| File | What |
|---|---|
| `/usr/data/opencreator/loadcell/loadcell.sh` | Sends the H commands over `ttyS7` at 9600 baud, the way stock `sendCmdToUart7` does: up to 5 tries, a reply is complete when it is longer than 12 bytes and contains `ok` |
| `loadcell.cfg` | `[gcode_shell_command loadcell]` (timeout 60, `verbose: True`), the three commands above and the wrappers below |

## Tare before probing

Stock tares with the nozzle off the bed before every probe session. `loadcell.cfg` does the same with `_LOAD_CELL_PREPARE`: save state, `G90`, `G1 Z5 F800`, restore state, `M400`, `LOAD_CELL_TARE`. The probe commands are renamed and wrapped so they call it first:

| Command | Wrapper |
|---|---|
| `PROBE` | `_LOAD_CELL_PREPARE`, then `_PROBE_BASE` |
| `PROBE_ACCURACY` | `_LOAD_CELL_PREPARE`, then `_PROBE_ACCURACY_BASE` |
| `PROBE_CALIBRATE` | `_LOAD_CELL_PREPARE`, then `_PROBE_CALIBRATE_BASE` |
| `BED_MESH_CALIBRATE` | `_LOAD_CELL_PREPARE`, then `_BED_MESH_CALIBRATE_BASE` |

## Homing Z

`G28` is renamed `G28.1`. After a Z home (a plain `G28`, or one that names Z), `_HOME_Z_PROBE` runs when X and Y are homed: `G1 Z10 F1500`, `G1 X107.5 Y107.5 F12000`, `PROBE HOME=Z`, `G1 Z5 F800`. The bed touch is then Z0. Without X and Y homed, Z homes to the switch only.

## Results

- The probe read -3.26 in the switch coordinates.
- After `PROBE HOME=Z`, a probe at the bed centre reads about -0.011.
- `[probe] z_offset` is -0.25, as stock. The mesh reads about -3.0 against the touch at -3.26. The first layer is still to be verified.
- Old meshes carry the -3.2 frame and must not be loaded.

## Limits

- `RUN_SHELL_COMMAND` ignores the script's exit code, so a failed tare does not stop a probe by itself.
- A `[probe]` `activate_gcode` cannot move, which is why the tare is in wrappers and not in the probe section.
- "Probe samples exceed samples_tolerance" appears when the board still has an old zero.
- Starting a probe with the nozzle on the bed gives "Probe triggered prior to movement".
