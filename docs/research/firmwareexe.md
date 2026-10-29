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
| `pin_loc_xy` / `pin_park_dist` / `cut_move_dist` / `cut_direction` | 14.0, -5.6 / 6 / 14.8 / left | park X20, cut to X-0.8 at Y-5.6 |
| `cut_fast_move_speed` / `cut_slow_move_speed` | 200 / 200 | F12000 |
| `cut_count`, `retract_length`, `pushback_length` | 1, 0, 0 | one cut, no pre-retract or pushback |
| `rip_length` / `rip_speed` | 5 / 10 | `G1 E-5 F600` |
| `purge_loc_xy`, `z_purge_move`, `purge_length` | 52.5, 230.5, False, 90 | chute, no Z move, first flush E90 |
| `brush_loc`, `brush_width`, `y_brush`, `brush_count`, `brush_clean_speed` | 69,230.5,-1, 8, False, 2, 200 | X65<->X73 at Y230.5, F12000 |
| `park_loc_xy` | 52.5, 230.5 | unload happens at the chute |
| `z_hop` (AFC.cfg) | 5 | `G1 Z(z+5)` |
| `kick` (AFC.cfg) | False | none |
| `tool_stn_unload` / `tool_unload_speed` | 60 / 10 | UnloadESpace / UnloadSpeed |
| toolhead sensor | `[ad5x_filament_sensor tool_start]` + `u1_filament_sensor_name: tool_start` | eboard PA3, 0.3 / 0.72 |

- Not mapped yet: flush volume from colours (`calc_flush_vol`), fan speeds per filament type, IFS-side feed lengths (AFC uses its own lane distances, to calibrate)

## Cut: stock against AFC_CUT

- `checkCrotchCutting(chn)`: IFS `F24 C<chn>` (turn the selector to that lane and clamp it), poll until the IFS state is 5 (ready); state 0x7f (homing error) -> `F15` re-home and retry. AFC does the same with `select_lane` before every lane move, nothing extra needed
- AFC_CUT with our vars vs stock:
  - approach: stock `Y10`, `Y-5.6` at the current X, `X20`; AFC safe move to X80 Y54.4 (when X <= 80, safe_margin 60,60) then diagonal to X20 Y-5.6. Stays at Y >= -5.6 and stops 6 mm before the pin; stock drives along the whole Y-5.6 strip, so it is clear
  - cut: same end point X-0.8, 200 mm/s (fast/slow both 200)
  - after: rip 5 mm at 10 mm/s = stock `G1 E-5 F600`; AFC adds 50 ms + 2x 200 ms dwell, evacuate to X20 and a post-cut safe move, then park (`ADX_PARK` goes X52.5 along the current Y, then into the chute like stock)
- AFC's diagonal approach is not what stock does, so `ADX_CUT` (in `AFC_IFS.py`, set as AFC's `tool_cut_cmd` when AFC.cfg has the default): stock `G1 Y10 F18000` (`cut_approach_y`), `G1 Y<pin_y>` at the current X, `G1 X<pin_x + pin_park_dist> F12000`, then `AFC_CUT`. Positions come from `_AFC_CUT_TIP_VARS`. `AFC_Macro_Vars.cfg`: `safe_margin_xy: 0, 0` (no AFC safe move), `post_cut_safe_move: False` (straight on to `ADX_PARK` like stock)
