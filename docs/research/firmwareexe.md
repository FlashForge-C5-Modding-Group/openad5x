# firmwareExe: filament change

What the stock `firmwareExe` 3.1.6 does for a filament change, from its decompile, and how the AFC settings map to it. Source paths in the binary are `../ad5x/serial/SerialObject.cpp`. It is a MIPS32 ELF, not stripped, with debug info.

## Settings (`/usr/data/config/Adventurer5M.json`)

| Key | Value | Use |
|---|---|---|
| `leftExtruderOffset.CutXOffset` / `CutYOffset` | 1.7 / 1.9 | cut position offsets |
| `leftExtruderOffset.xOffset` / `yOffset` | 0 / 1.5 | x/y passed to purge and brush |
| `Multicolour.UnloadESpace` | 60 | extruder retract on unload (mm) |
| `Multicolour.UnloadIFSSpace` | 70 | IFS retract (mm) |
| `Multicolour.UnloadSpeed` | 600 | mm/min |
| `general.FilamentSenserMin` / `Max` | 0.3 / 0.7 | stored, but the check uses 0.3 / 0.72 (below) |
| `general.zLevelOffset` | -3.234 | stock z offset (the old -3 mesh) |

## Toolhead filament sensor (`SerialObject::checkFilamentSenser`)

- `GET_FILAMENT_VALUE` (stock `query_adc.py`, eboard PA3 read as a "temperature" ADC), present when `value <= 0.3 || value >= 0.72`
- Kalico: `QUERY_ADC NAME='temperature_sensor filamentValue'` read 0.319 with no filament in the toolhead (cut sensor PA2: 0.508)

## Change (`SerialObject::changeChannel`)

1. `M400`, `M114` (save X/Y), `G1 Z(z+5)` (or Z220 if z > 220), `M400`
2. `doLoadAndUnload(new, old)`:
   - `cutFilament(old)` when the toolhead sensor shows filament, else `checkCrotchCutting`
   - IFS `F11 C<old> ... 1200` (unload), `checkRefulling`, then IFS feed of the new lane (`F10`-type, up to 650 mm at 1200 mm/min) until `checkFeeding` / the toolhead sensor
3. wait for nozzle temperature, `getFlushVol` (from the two lane colours, `calc_flush_vol`)
4. `cleanFilamentBox` once, twice when flush volume > 400
5. `SET_FAN_SPEED FAN=fanM106 SPEED=..`, `G1 Y<saved>`, `M400`, `G1 X<saved>`, `M400`, `G1 Z<saved>`, `M400`, `G92 E<saved>`, `SDCARD_CLEAR_REFUELLING`

## Cut (`fourInOneCut` + `cutFilament`)

```
M400
G90
G1 Y10 F18000
G1 Y{CutYOffset - 7.5}          ; -5.6
G1 X20 F12000
G1 X{CutXOffset - 2.5}          ; -0.8, pushes the cutter lever (front left)
M400
G92 E0
G1 E-5 F600
M400
printClearGoPos: G1 X{x + 52.5}, G1 Y220 F12000, G1 Y{y + 229}, M400
G92 E0
IFS: F11 C<chn> <speed>  and  G1 E-<UnloadESpace> F<UnloadSpeed>  (together)
```

## Purge and brush (`cleanFilamentBox`, `flushFilament*`, `clear_brush`)

- `G1 X{x + 52.5}`, `G1 Y{y + 229}` (X52.5 Y230.5), `M400`
- `flushFilamentFrist`: `M106 S<fan>`, `G92 E0`, `G1 E90 F<type speed>` while the IFS pushes the new lane, `M106` second speed
- `flushFilamentBrush`, `flushFilamentSecond` (rest of the flush volume), `flushFilamentBrush`
- brush: `G1 Y220 F3000`, `G1 X78 F12000`, `G1 Y{y + 229}`, `X65`, `X73`, `X65`, `X73`, `X65`, `X78`, `G1 Y220`, `M400`
- end: IFS `F23 C<chn>`

## AFC mapping (`AFC/AFC_Macro_Vars.cfg`, `AFC/AFC_Hardware-IFS.cfg`)

| AFC | Value | Stock |
|---|---|---|
| `pin_loc_xy` / `pin_park_dist` / `cut_move_dist` | 14.0, -5.6 / 6 / 14.8 | park X20, cut to X-0.8 at Y-5.6 |
| `z_hop` (AFC.cfg) | 5 | `G1 Z(z+5)` |
| `kick` (AFC.cfg) | False | none |
| `tool_stn_unload` / `tool_unload_speed` | 60 / 10 | UnloadESpace / UnloadSpeed |
| toolhead sensor | `[ad5x_filament_sensor fill_sensor]` + `u1_filament_sensor_name: fill_sensor` | eboard PA3, 0.3 / 0.72 |

- Not mapped yet: flush volume from colours (`calc_flush_vol`), fan speeds per filament type, IFS-side feed lengths (AFC uses its own lane distances, to calibrate)

## Cut

- `checkCrotchCutting(chn)`: IFS `F24 C<chn>` (turn the selector to that lane and clamp it), poll until the IFS state is 5 (ready); state 0x7f (homing error) -> `F15` re-home and retry. AFC does the same with `select_lane` before every lane move, nothing extra needed
- `ADX_CUT` (in `AFC_IFS.py`, set as AFC's `tool_cut_cmd`) does the stock cut itself: `G1 Y10 F18000`, `G1 Y<pin_y> F1800` at the current X, `G1 X<pin_x + pin_park_dist> F12000`, `G1 X<pin_x - cut_move_dist> F600`, then `G1 E-5 F600`. Positions come from `_AFC_CUT_TIP_VARS`
