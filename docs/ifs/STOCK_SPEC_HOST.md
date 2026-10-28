# Stock AD5X host (`firmwareExe`) filament handling: spec to match

Source: static analysis (Ghidra 12.2 headless, read only). Binary: `extracted\software-3.1.6\firmwareExe`, md5 `53002874d76d1b381e45d4b533884408` (md5 read from the Ghidra program itself), MIPS32, not stripped. Addresses are function entry points (`SerialObject::` unless stated). The F112 analysis is in `STOCK_HOST_RELEASE.md` and is not repeated; `firmwareexe/NOTES.md` has the printer config values and the AFC mapping.

Conventions used below
- "G:" = G-code sent to Klipper through `sendGcodeCmd` (JSON-RPC `gcode/script` on the Klipper API socket). The 4th argument 1 means wait for the reply (Klipper replies when the command is queued, not when the move is done, hence the many `M400`). Only `cutFilament`'s `G1 E-60` and the `SAVE_GCODE_STATE` in the pause path are sent with wait = 0.
- "IFS:" = text command to the IFS over ttyS4 via `sendCmdToUart4` (mutex, `tcflush`, write `"<cmd> \r\n"`, `usleep(100000)`, then `select` with 2 s timeout for the reply; `Serial::sendToUart4WaitRecv` 005dc760). Only `F13` and `F19` are sent when the IFS is flagged absent (`this+0x2e2 == 0`); everything else returns "" without sending.
- Reply parse everywhere: split on `[: ]`, field 3 = state: **5 = move done/idle, 0x7f = error (homing/driver), 0x7e = busy/timeout**. Some functions also read fields 5 and 11 of the same reply (`checkPurgeOldFilament`). F-code meanings as in `NOTES.md` line 39: F10 feed, F11 exit/retract, F12 sensors, F13 status, F15 re-home, F23/F24 channel select, F39 release, F112 stop.
- `Lnnn Snnn` on F10/F11: L = length mm, S = speed (same units as G1 F, mm/min).
- "toolhead sensor" = `checkFilamentSenser` 005f1af4: sends G `GET_FILAMENT_VALUE`, parses `value:<float>`; filament present iff `value <= 0.3 || value >= 0.72`. (Stock `query_adc.py`: eboard PA3 ADC, object `temperature_sensor filamentValue`; the second ADC `cutValue` PA2 is the cutter sensor, reported as `query_adc.cut`.)
- Cancel flag = `this+0x2e3`; pause flag = `this+0x8a`; "polling-busy" flag `this+0x2f0` (set 1 inside feed/load/cut waits so the status thread `recvQueryFourInOneSt` stays quiet).
- Config values are in `/usr/data/config/Adventurer5M.json` (`leftExtruderOffset.{xOffset,yOffset,zOffset,CutXOffset,CutYOffset}`, `Multicolour.*`, `FFMInfo.channel`); getter defaults in the binary: xOffset 0, yOffset 0, CutXOffset 0, CutYOffset 0, `channel` 1, UnloadESpace 60, UnloadIFSSpace 70, UnloadSpeed 600 (those three are only read by `initMulticolourConfig` and UI time estimators, not used as command lengths). Values on the user's printer (from `NOTES.md`): xOffset 0, yOffset 1.5, CutXOffset 1.7, CutYOffset 1.9.
- Below, `px = xOffset`, `py = yOffset` (these are what `Config::getLeftExtruderXOffset/YOffset` return and what is passed as the x/y arguments of every purge/brush/clear function).

---

## 1. Klipper side that triggers a toolchange (stock `virtual_sdcard.py`, software-3.1.6)

Not part of the host binary, but it is the trigger.
- Host sends once at print start: `SDCARD_SET_CHANNEL CHANNEL=<first chn>` (sets `load_channel` and `print_channel`) and `SDCARD_ENABLE_FFM ENABLE=1` only if (IFS present `this+0x2e2` && multicolour job && `this+0x290 >= 2`), else `ENABLE=0`.
- While printing from the file, a line that is exactly `T0..T15` and `enable_ffm` is **consumed, not executed**: `print_channel = n`; if `n != load_channel`: run `M400`, set `change_filament = True` and poll every 0.5 s until the host sends `SDCARD_CLEAR_REFUELLING` (or the print is paused/cancelled); then `load_channel = print_channel`, continue with the next line.
- Host polls `objects/query` (list in `sendGcodeCmd` case 3): `virtual_sdcard[is_active, progress, file_position, file_size, channel, refuelling]`, `pause_resume.is_paused`, `fan_generic fanM106/chamber_fan/external_fan/internal_fan.speed`, `print_stats[filename, filament_used, state]`, `toolhead.homed_axes`, `gcode_move[gcode_position, absolute_extrude, speed]`, `webhooks.state`, `extruder[temperature,target]`, `heater_bed[temperature,target]`, `query_adc[value,cut]`, `exclude_object.clear_mem`. `doQueryResponse` stores `refuelling` in the `m_refulling` field (`this+0x2e0`, the only writer besides init/changeChannel) and `channel` in `m_channel`. No temperature command is issued by the T line: the nozzle target for the new filament is whatever the sliced G-code set before `Tn` (see 5.3).

---

## 2. Per-filament-type tables (type string from `FFMInfo` for the channel, `getChnFilamentType`; default "PLA" if empty)

Compared by exact string: `PLA`, `PETG`, `TPU`, `SILK`, `PLA-CF`, `PETG-CF`, `PC-ABS`. Any other string (including `ABS`, `PLA-CF`, `PETG-CF` where not listed) takes the "other" column.

| function (addr) | PLA | PETG | TPU | SILK | PLA-CF / PETG-CF / other |
|---|---|---|---|---|---|
| `getFilamentTypeFristSpeed(chn,false)` 005e3c68 = feed F of first flush `G1 E90` | 300 | 300 | 100 | 150 | 300 |
| `getFilamentTypeFristSpeed(chn,true)` = fan S (0-255) during first flush | 0 | 51 | 51 | 51 | 0 |
| `getFilamentTypeSecondSpeed(chn,false)` 005e3f44 = feed F of second flush | 300 | 300 | 100 | 150 | 300 |
| `getFilamentTypeSecondSpeed(chn,true)` = fan S after flush | 125 | 102 | 102 | 102 | 125 |
| `getFilamentTypeUnloadSpeed` 005e4070 (F11 S and `G1 E-60 F`) | 600 | 300 | 200 | 300 | 600 |
| `getFilamentTypeUnloadSpace` 005e41b0 | 60 | 60 | 60 | 60 | 60 |
| `getFilamentTypeTemp` 005e459c (end-of-print purge only) | 220 | 250 | 230 | 230 | 220 (PETG-CF 250, PC-ABS 250) |
| `getFilamentTypeTime` 005e3db8 (s, `checkPurgeOldFilament` wait) | 15 | 15 | 36 | 36 | 15 |
| `getFilamentTypeLoadFristSpace` 005e42e4 | 80 | 70 | 80 | 80 | 80 | (no caller found: dead) |
| `getFilamentTypeLoadSpace` 005e445c | 60 | 50 | 50 | 60 | 60 (PETG-CF 40) | (no caller found: dead) |

Notes: the string at 0x00adcde8 is `PETG`, at 0x00adcdf0 is `TPU`. `FristSpeed` and `SecondSpeed` take (chn, bool): bool true returns the fan value, false the feed rate.

---

## 3. Primitives (exact sequences)

### 3.1 `printClearGoPos(x=px, y=py)` 005ed008 (park at purge chute)
G: `G1 X<px+52.5> F12000`, `G1 Y220 F12000`, `G1 Y<py+229> F3000`, `M400`. Numbers formatted `'f'`, 2 decimals (`QString::number(v,'f',2)`). Constants: double 52.5 at 0x00ae04f0, float 229.0 at 0x00ae04f8. With px 0, py 1.5: X52.50 then Y220 then Y230.50. X is moved first at whatever Y the head is at.

### 3.2 `fourInOneCut(chn, x, y)` 005f5860 (cutter)
G, in order: `M400`, `G90`, `G1 Y10 F18000`, `G1 Y<CutYOffset-7.5> F1800`, `G1 X20  F12000` (two spaces in the literal), `G1 X<CutXOffset-2.5> F600`, `M400`, `G92 E0`, `G1 E-5 F600`, `M400`, then `printClearGoPos(x,y)`, then IFS `checkCrotchCutting(chn)` (3.3), then `M400`. (Constants: doubles 7.5 at 0x00ae04e0 and 2.5 at 0x00ae04e8. With CutY 1.9, CutX 1.7: Y-5.60, X-0.80.) The cutter lever is pushed by the X move at F600; there is no second cut or dwell.

### 3.3 `checkCrotchCutting(chn)` 005f4f8c (select/clamp lane)
IFS `F24 C<chn>`; set busy flag; loop: IFS `F13`, parse state; exit when state == 5, or after 21 polls (counter > 0x14), or on cancel; on 0x7f: send `F15`, then `F24 C<chn>` again, counter reset to 1; state 0x7e: leave the loop. `sleep(1)` between polls (about 21 s worst case). No error is raised here.

### 3.4 `checkCrotchF39(chn)` 005f8da0 (release)
IFS `F39 C<chn>`, then the same poll shape as 3.3 (F13, 1 s, up to about 11 polls, 0x7f -> `F15` and resend `F39 C<chn>`).

### 3.5 `cutFilament(chn, x, y)` 005f5e58
`fourInOneCut(chn,x,y)`; G `G92 E0`; IFS `F11 C<chn> L60 S<UnloadSpeed(type)>` (sent first); G `G1 E-60 F<UnloadSpeed>` (`UnloadSpace` = 60, sent without waiting, so the lane retract and the extruder retract overlap). Returns 0. The `L60` is a literal, not a config value.

### 3.6 `checkRefullingFrist(chn)` 005f2478 / `checkRefulling(chn)` 005f1d84 (wait for old filament to leave the toolhead)
Poll IFS `F13` every 1 s (`sleep(1)`); `checkRefullingFrist`: when the toolhead sensor reads empty, IFS `F112` (resent if the reply lacks "ok") + `M400`, return 0. Returns: 1 cancel, 4 if state 5 persists for more than 10 polls while the sensor still reads filament, 8 on state 0x7f, 10 after 11 polls of 0x7e. `checkRefulling` is the same poll without the F112 and is used for the second pass.

### 3.7 `fourInOneUnLoad(chn, flag)` 005f616c (lane retract until toolhead clear)
Polls IFS `F13` (usleep-based, 200 ms); every time the IFS is idle (state 5) and the toolhead sensor still shows filament it re-clamps (`checkCrotchCutting`, `F24`) and sends `F11 C<chn> L70 S600`; three times with `L70`, then a last one `F11 C<chn> L60 S600` (literals " L70 S" x3 and " L60 S", S = 0x258 = 600). On 0x7f: `F15`, `checkCrotchCutting`, resend. Ends when the sensor reads empty or on timeout ("Unload timeOut!").

### 3.8 `checkFeeding(chn)` 005f9674 (wait for toolhead sensor after a long feed)
Busy flag set. Loop with `usleep(100000)` per turn: IFS `F13`, state:
- 5 and pause flag (`+0x8a`): IFS `F112`, return 7.
- 5 after the retry phase and not yet re-fed: `checkCrotchCutting(chn)` then IFS `F10 C<chn> L500 S1200`, once.
- 0x7f: return 8 (caller sends `F15`). 0x7e more than 100 times: return 10 ("IFS home error").
- toolhead sensor reads filament: IFS `F112`, return 0.
- cancel flag: IFS `F112`, return 1.
- 301 turns (about 30 s) without sensor: first time send IFS `F11 C<chn> L5 S1200` (back off 5 mm) and enter retry phase, counter 0; second time (another 30 s): `sigIFSError(E0100+chn-1)` (see 6), `checkCrotchF39(chn)`, return 3.
Returns 0 and 7 are success.

### 3.9 `checkLoad(chn, S)` 005fbaa0 (flush-time feed wait)
Used by the first flush. Poll IFS `F13` every 1 s. State 5: if toolhead sensor reads filament send `F112` and return 0; state 5 with sensor empty: continue counting. 0x7f: `F15`, `checkCrotchCutting(chn)`, IFS `F10 C<chn> L30 S<S>`, sleep 1, return code 8 path (restart loop). 0x7e more than 10: return 10. After 6 polls: once `checkCrotchF39(chn)`. After 31 polls: first time `checkCrotchCutting(chn)` + IFS `F10 C<chn> L50 S<S>` and counters reset; second time `sigIFSError(E0100+chn-1)`; loop-top retry after `timeOutPause()` resends `F10 C<chn> L600 S<S>`. S is the speed given by `flushFilamentFrist`.

### 3.10 Flush pieces
`flushFilamentFrist(chn)` 005fc930 (type = type of channel `Config::getChannel`, i.e. the channel just set; chn argument is the lane to feed):
1. G `M106 S<FristSpeed(true)>`
2. G `G92 E0`
3. G `G1 E90 F<FristSpeed(false)>`
4. IFS `F10 C<chn> L90 S<FristSpeed(false)>` (lane pushes in step with the extruder)
5. `checkLoad(chn, FristSpeed(false))` (3.9). If it returns 1 (cancel) stop. Else `checkCrotchF39(chn)`, G `M400`, G `M106 S<SecondSpeed(true)>`.

`flushFilamentSecond(chn)` 005ee3ec:
1. G `M106 S<FristSpeed(true)>`; `sleep(1)` three times (3 s, aborted by cancel)
2. G `G92 E0`; G `G1 E90 F<SecondSpeed(false)>`; G `M400`
3. G `M106 S<SecondSpeed(true)>`

`flushFilamentBrush(second, x=px, y=py)` 005ee7dc:
1. `sleep(1)` x3 (3 s, ooze cool-down, abort on cancel)
2. if `second == true`: G `G92 E0`, `G1 E-3 F300`, `M400`, `G92 E0`
3. G `G1 Y220 F12000`, `G1 Y<py+229> F3000`, `G1 Y220 F12000`, `G1 Y<py+229> F3000`, `G1 Y220 F12000`
4. if `second == false`: G `G1 X<px+52.5> F12000`, `G1 Y<py+229> F3000`
5. G `M400`

`cleanFilamentBox(newChn, flushVol, x=px, y=py)` 005fce9c (one purge pass):
G `G1 X<px+52.5> F12000`, `G1 Y<py+229> F3000`, `M400`; `flushFilamentFrist(newChn)`; `flushFilamentBrush(false)`; `flushFilamentSecond(newChn)`; `flushFilamentBrush(true)`; IFS `F23 C<newChn>`. The `flushVol` argument is not used inside (see 4). Extruder amount per pass: 90 + 90 = 180 mm; first 90 mm have the lane pushing 90 mm (`L90`).

`clearCurrentChnFilament(chn,x,y)` 005eeedc: `printClearGoPos`, `flushFilamentSecond(chn)`, `flushFilamentBrush(false)`.

`clearAllFilament(x,y)` 005f3e14: up to 8 times: `clearCurrentChnFilament`; stop when the toolhead sensor reads empty, then G `G1 Y220 F12000`, `M400`, return 0; between tries `sleep(1)`; after 8 tries `clearOldFilament` and return 1. Cancel/pause returns 1.

`clear_brush(y)` 005ed4d0 (X brush, used at resume and at leveling, not in toolchange): G `G1 Y220 F3000`, `G1 X78 F12000`, `G1 Y<y+229> F3000`, `G1 X65 F12000`, `G1 X73`, `G1 X65`, `G1 X73`, `G1 X65`, `G1 X78`, `G1 Y220`, `M400`. `clearBrush(y)` 005ed968 is identical without the final `G1 Y220`.

`checkPurgeOldFilament(chnIdx, x, y)` 005f454c (print start, filament already at the toolhead): if toolhead sensor reads empty return; else G `M106 S<FristSpeed(true)>`, `G92 E0`, `G1 E90 F<FristSpeed(false)>`; poll IFS `F13` every 1 s up to `getFilamentTypeTime` s (fields 5 and 11 of the reply are checked for "idle" for more than that many consecutive polls); G `M400`, `M106 S<SecondSpeed(true)>`; `flushFilamentBrush(false)`; if the lane still reads loaded: up to 8 times `clearCurrentChnFilament` until the toolhead sensor reads empty (sleep 1); G `M400`, `G92 E0`.

---

## 4. Flush volume

`getFlushVol(oldChn, newChn)` 005f2cd4 = `calc_flush_vol(...)` 005cc724 on the lane colour strings (`FFMInfo` colour 1..4, parsed with `QColor::setNamedColor`). Result is integer, clamped 60..800.

Algorithm (constants from the data section): colours as r,g,b/255; HSV via `RGB2HSV`; for old colour (src) and new colour (dst):
- `lum = 0.3*r + 0.59*g + 0.11*b`
- `dxy = hypot( cos(h1)*s1*v1 - cos(h2)*s2*v2 , sin(h1)*s1*v1 - sin(h2)*s2*v2 )` with h in degrees converted by `/180*pi`; `dhs = min(dxy, 1.2)`
- if `lum_dst >= lum_src`: `lumi = (lum_dst - lum_src)^0.7 * 560`
- else: `lumi = (lum_src - lum_dst) * 80` and `dhs = min(dhs, 0.67*v_dst + 0.33*v_src)`
- `hs = dhs * 230`
- `vol = sqrt(hs^2 + lumi^2 + hs*lumi)` (law of cosines, cos = -0.5); if `vol < 60` -> 60; else `(int)vol`, max 800.
This is the same shape as the OrcaSlicer/BambuStudio flush-volume formula.

Call-site quirk (as compiled): `getFlushVol` calls `calc_flush_vol(R1,G1,B1,0xff, R2,G2,B2,0xff)` but the function reads its first parameter as alpha and parameters 2..4 as R,G,B. Effective inputs: if `R1 == 0` the src colour is treated as transparent (white); otherwise src colour = (G1, B1, 255)/255. Same for dst with R2. So red is only used as an on/off flag and blue is always 255. Reproduce this only if exact stock numbers are wanted.

Use of the result (changeChannel 005fe970): only to choose the number of purge passes: `passes = 1 + (vol > 400)`; each pass is one `cleanFilamentBox`, followed by `M400`. The extruder amount per pass is constant 180 mm. No matrix, no per-pass E scaling. `Config` has no flush multiplier. Colour mapping: `getFlushVol(oldChn = Config::getChannel() before the change, newChn)`.

---

## 5. Flows in call order

### 5.1 First load / auto-insert (idle, spool inserted)
Trigger: `recvQueryFourInOneSt` 005fa660 sees a lane sensor bit rise (mask `this+0x298`) while not printing -> `checkFourInOneLoad(newMask, enabledMask)` 005fa288, lanes 1..4:
1. `sigAutoLoad(chn)` (UI dialog "auto load")
2. `fourInOneLoadFristStep(chn)` 005f839c: toolhead sensor read once at the start and kept (`local_44`); it never aborts on it (the function returns only 0, 1 or 10). `checkCrotchCutting(chn)` (F24); IFS `F10 C<chn> L650 S1200` (0x28a, 0x4b0); poll IFS `F13` every 100 ms (`usleep(100000)`), up to 0x78 = 120 polls, stop when the toolhead sensor reads filament only if it read empty at the start; if it already read filament at the start the sensor is ignored and the feed runs to the poll limit or the end of the move; 0x7e more than 10 -> return 10; 0x7f: `F15`, `checkCrotchCutting`, resend `F10 C<chn> L650 S1200`; on stop: IFS `F112`.
3. `fourInOneLoadSecondStep(chn)` 005f7b4c: IFS `F11 C<chn> L100 S1200`; poll `F13` every 200 ms until state 5; 0x7f: `F15`, `checkCrotchCutting`, resend `F11 ... L100 S1200`.
4. IFS `F23 C<chn>`; `checkCrotchF39(chn)` (`F39 C<chn>`).
Return 10 -> dialog `E0114: IFS ... home error!` and `sigIFSError(.., E0114)`. No heating, no flush and no G-code in this path; extruder is not moved. Lane parks 100 mm back from the sensor trip point.

Pause-time insert (`checkPauseAutoLoad` 005fade4, from `ifsPaused`): `clearAllFilament(px,py)`, `checkCrotchCutting(chn)`, IFS `F10 C<chn> L200 S1200`, poll `F13` 1 s, IFS `F23 C<chn>`, `checkCrotchF39(chn)`.

### 5.2 Load at print start (`serialPrint` 006042e4, normal start, IFS present, multicolour)
Before `serialPrint`: the Print screen has set bed target (`setPlatformHeat` -> G `M140 S<t>`) and, once the bed has arrived (`waitArriveTemperature(false,false,true)`), `setRightNozzleTemp` -> G `M104 S<job nozzle temp>` (job temp from the G-code header scan in `Print::initWidget`: strings `M104`, `M109`, `M140`, `M141`, `M190`, `T0`; chamber target > 0 delays the nozzle). `setRightNozzleTemp` sends `M104 S0 T0` instead if the nozzle sensor reads below -10 (float at 0x00aeae3c), otherwise `M104 S<t>`; bed likewise `M140 S0` / `M140 S<t>`. The per-type temperature table (section 2) is NOT used here.
`serialPrint` start, in order:
1. G `G92 E0`
2. G `CLEAR_PAUSE`; G `SET_FAN_SPEED FAN=pcb_fan SPEED=1`
3. Non-IFS or non-multicolour print: G `G1 Z10 F500`, `G92 E0`, `flushFilamentSecond(chn-1)`, `flushFilamentBrush(true,px,py)`, `M106 S0`. (Then straight to step 6.)
4. IFS print: `checkPurgeOldFilament(chn-1, px, py)`; `checkPrintUnLoad(laneMask, currentLoadedChn, px, py)` 005f6e58: toolhead empty -> proceed; else once `cutFilament(cur)`, then `fourInOneUnLoad(cur,false)` if its lane bit is set, else try `fourInOneUnLoad(lane,true)` on the other lanes with filament; if the toolhead still reads filament after all four: IFS `F23 C<cur>` and `sig_extruderSensorAbort` (E0113), return 0.
5. `changeChannel(mode=1, firstChn, px, py)` (5.3 without the Z lift/return): `doLoadAndUnload(new=first, old=Config::getChannel, flag=1)`, wait for nozzle, `getFlushVol`, `Config::setChannel(first)`, `cleanFilamentBox` x passes, then `SET_FAN_SPEED FAN=fanM106 SPEED=<this+0x228>`, `M400`, `SDCARD_CLEAR_REFUELLING`. Then `operationFilament(chn,4,0,chn)` (UI state).
6. G `M21`; G `M23 <path under /usr/data/gcodes>`; G `M26 S<seek>`; G `SDCARD_SET_CHANNEL CHANNEL=<n>`; G `SDCARD_ENABLE_FFM ENABLE=0|1`; G `M24`. `EXCLUDE_OBJECT NAME=<n>` lines are sent for excluded objects between M26 and M24.
Prime/first layer: the host sends no prime line or first-layer move; it is all in the sliced file. (`Print::doPreparation`/`checkZ` is the leveling prep: `BED_MESH_CLEAR`, `G1 Z50 F3000`, `M106 P0 S255`, `G1 X60 Y-3 F12000`, `G1 X130 F1200`, `G1 X150 F1200`, `G1 Z5 F600/F800/F6000`, `BED_MESH_PROFILE LOAD|REMOVE=...`; not part of a normal print start.)

### 5.3 Toolchange during print (`changeChannel(mode=0, newChn, px, py)` 005fe970)
Trigger: `refuelling` (+0x2e0) true while IFS multicolour print is running (serialPrint main loop, 50 ms `usleep` poll). If the previous state flag `local_a0 == 1` (a runout was already detected) `clearAllFilament(px,py)` runs first (result 1 -> pause flag set, state 2). Else call straight in:
1. G `M400`; save state (`this+0x134=1`, `+0x140`, `+0x138=newChn`; power-loss file written via `PowerSavingModeFile::setPowerSavingMode`).
2. G `M114`; parse `X:` and `Y:` (saved); saved Z is `this+0x2ec` (from `gcode_position`).
3. Z lift (mode 0 only): `z' = (z > 220) ? 220 : z + 5` (doubles 220.0 at 0x00aeae60, 5.0 at 0x00aeae68). G `G1 Z<z'> F800`, G `M400`.
4. `doLoadAndUnload(new, old = Config::getChannel(), px, py, flag=0)` 005fda70 (5.4). Returns: 1 cancelled (return 1 from changeChannel); 6 no filament available (changeChannel returns 6 -> caller sets the pause flag, state 2); 9 lane substituted by autodetect (new = lane found); else continue.
5. Wait for nozzle temperature: loop `sleep(1)` until `nozzle real >= nozzle target` and `target > 0` (integer compare, no tolerance, no timeout), or until the pause flag is set. The target is whatever the file/slicer already set before `Tn`; the host does not choose a temperature here (no M104/M109 in changeChannel, doLoadAndUnload, cleanFilamentBox, flushFilament*). Rule between old and new type: not applied by the host. (Searched all callers: `getFilamentTypeTemp` is called only from the end-of-print cleanup, 5.7.)
6. `fanSave = this+0x224 -> this+0x228`. `getFlushVol(old, new)` (section 4). `Config::setChannel(new)`.
7. `passes = 1 + (vol > 400)` x { `cleanFilamentBox(new, vol, px, py)` (3.10); G `M400` }.
8. UI update (`printChnFilament`); `this+0xd0 = 1` (mode 0); clear change flag; power-loss state saved.
9. G `SET_FAN_SPEED FAN=fanM106 SPEED=<this+0x228>`
10. mode 0 only: G `G1 Y<savedY> F12000`, `M400`, `G1 X<savedX> F12000`, `M400`, `G1 Z<savedZ> F800`, `M400`, then `G92 E<this+0xbc>` if `this+0xbc >= 0` else `G92 E0`.
11. G `M400`; `this+0x2e0 = 0`; G `SDCARD_CLEAR_REFUELLING` (releases Klipper).

### 5.4 `doLoadAndUnload(newChn, oldChn, x, y, flag)` 005fda70
Start: if the toolhead sensor reads filament and loaded-chn (`this+0x24c`) != newChn, or `flag == 0`: `cutFilament(oldChn,x,y)` (3.5) and treat as needing unload; else (flag 1, nothing to unload) `checkCrotchCutting(newChn)`.
Loop until done/cancel (each iteration ends `sleep(1)`):
- Unload phase (while unload pending):
  - `checkRefullingFrist(oldChn)` (3.6): result 8 -> IFS `F15`, `checkCrotchCutting(old)`, IFS `F11 C<old> L50 S1200`, sleep 1, repeat; 4 -> if a second cut was already done: `sigIFSError(E0104+old-1)` (getIFSUnLoadErrorCode) + `checkCrotchF39(old)` + pause; else `cutFilament(old)` again, sleep 1; 10 -> dialog `E0114` (IFS home error, channel number appended), sleep, pause path; 1 -> return 1; 0 -> IFS `F11 C<old> L70 S1200` (first time), sleep 1, then second pass with `checkRefulling(old)` (same codes, resend uses `checkCrotchCutting` instead).
- Load phase: read the lane mask (`this+0x298`); if the new lane bit is clear: count 1 s ticks; after 11 ticks `autoDetectLoad(new, ...)` (finds another lane with the same type string and same colour string among lanes with filament, sets the slot->lane map `this+(slot+0x94)*4`, and unless suppressed runs `doAutoDetectLoad`); if none: `autoLoadNoFilamentPause` (UI), G `M25`, pause flag, return 6. If the lane has filament: IFS `F10 C<new> L1000 S1200` (0x4b0), `checkFeeding(new)` (3.8):
  - 0 or 7 -> done (9 if lane was substituted);
  - 8 -> IFS `F15`, `checkCrotchCutting(old/param)`, sleep 1, retry;
  - 3 or 10 -> `timeOutPause()` (user pause dialog), on resume re-select lane and retry;
  - 1 -> cancel.
- On success G `M400` and return.
`doAutoDetectLoad(chn)` 005fd288: `checkCrotchCutting(chn)`, IFS `F10 C<chn> L1000 S1200`, `checkFeeding(chn)` (3 -> fail), `Config::setChannel(chn)`, `cleanFilamentBox(chn, 0, px, py)`.

### 5.5 Runout (lane empty while printing, `serialPrint` main loop)
Each 50 ms tick: if the current slot's lane bit in `this+0x298` is clear: counter++; at 20 ticks (about 1 s): if the toolhead sensor still reads filament, compute `filament_used - baseline`; while that is <= 600 mm (float at 0x00aeae40) set state 1 and keep printing (the filament left in the tube is used up); else (toolhead empty or more than 600 mm extruded): G `SAVE_GCODE_STATE NAME=PAUSE_state` (no wait), G `M25`, wait for pause, G `G1 Z<min(z+5,220)> F800`, `clearCurrentChnFilament`, `autoDetectLoad(...)` for a lane with the same type+colour; success: G `RESTORE_GCODE_STATE NAME=PAUSE_state MOVE=1 MOVE_SPEED=100`, `M400`, resume; failure: state 2 and the normal pause path (5.6) with `autoLoadNoFilamentPause` dialog.

### 5.6 Pause / resume / cancel
Pause (pause flag `+0x8a`, user or runout, `serialPrint`):
1. `printPause()`; G `M25`; G `SAVE_GCODE_STATE NAME=PAUSE_state` (no wait) (skipped if state 2).
2. save Z (`this+0xb8`), G `SET_IDLE_TIMEOUT TIMEOUT=864000`; save nozzle and bed targets (`+0x15c`, `+0x160`), fan `+0x228 = +0x224`.
3. wait until the Klipper `pause_resume.is_paused` state arrives (6 polls then resend M25, max 31).
4. `setRightNozzleTemp(0)` (G `M104 S0`), G `M106 S255`, G `G1 Z<min(z+5,220)> F800` (if z <= 220 add 5.0).
5. `printClearGoPos(px,py)`; `operationFilament(chn,6,0,chn)`; `printPauseFinish`; G `SET_STEPPER_ENABLE STEPPER=extruder ENABLE=0`; G `M106 S0`.
6. No IFS: wait (200 ms poll) until the pause flag clears. IFS: `ifsPaused()` 005fb334 (polls F13, lets the user insert a spool -> `checkPauseAutoLoad`).
Resume: `printResume()`; `resumePrintPreHeating` (G `M104 S<saved>`, `M140 S<saved>`); `sleep(3)`; wait `waitArriveTemperature(false,true,true)` (nozzle within -2..+5 of target, bed within -2..+5 of target; target < 30 nozzle / < 10 bed counts as arrived) with `sleep(1)`; G `SET_STEPPER_ENABLE STEPPER=extruder ENABLE=1`; G `SET_IDLE_TIMEOUT TIMEOUT=864000`; `printClearGoPos`; `flushFilamentSecond(slotChn)`; `flushFilamentBrush(false)`; G `SET_FAN_SPEED FAN=fanM106 SPEED=<saved>`; G `G90`; `clear_brush(py)`; `printResumeFinish`; if a toolchange was pending (`+0x2e0`): `changeChannel(0, ...)` first, else G `RESTORE_GCODE_STATE NAME=PAUSE_state MOVE=1 MOVE_SPEED=100`, `M400`, `M24`, poll VS state until printing again (max 31 s, resend `M24` after 6).
`timeOutPause()` 005fb804 (used by feed/load timeouts): `sigTimeOutPause` (dialog), G `SET_IDLE_TIMEOUT TIMEOUT=864000`, `pausePrintDo` (G `M104 S0`, `M106 S0`), `operationFilament(chn,6)`, `printPauseFinish`, extruder disable, `ifsPaused()`, then resume as above (`sleep(3)`, wait temperature, `operationFilament(chn,4)`, `printResumeFinish`, extruder enable).
Cancel: UI/`this+0x88`: G `CANCEL_PRINT`; cancel flag `+0x2e3` makes every wait above return early (F112 is sent by `checkFeeding` and `checkLoad` only in the listed branches); then the end-of-print cleanup (5.7) runs with `printCancel()`.

### 5.7 End of print (also after cancel)
1. G `M400`; `M114` read Z; park Z ladder: `z<=50 -> 100`, `50<z<=100 -> 150`, `100<z<=150 -> 200`, else 220 (doubles at 0x00aeaea8.. 0x00aeae90); G `G1 Z<that> F800`; G `M400`; `powerSavingParamClear`; `printClearGoPos(px,py)`.
2. If IFS and not error and state != 1: (a) current lane empty but toolhead reads filament: `printCleanAllFilament`, `setRightNozzleTemp(getFilamentTypeTemp(chn))` (section 2: 220/230/250), then up to 7 times { wait nozzle arrived (`waitArriveTemperature(false,true,false)` 1 s poll), `clearCurrentChnFilament`, until toolhead reads empty }; (b) lane has filament and toolhead reads filament: `cutFilament(chn)` then `fourInOneUnLoad(chn,false)`; then `checkCrotchF39(chn)`. Then `clearChnStatus()` 005e3584 (IFS `F23 C1`..`F23 C4`) and `operationFilament(0,0,0,0)`.
3. G `SET_IDLE_TIMEOUT TIMEOUT=1800`, `setRightNozzleTemp(0)` (`M104 S0`), `setPlatformHeat(0)` (`M140 S0`), `initPrinterFan`, G `M220 S100`, `M400`, `G92 E0`, `BED_MESH_CLEAR`, `BED_MESH_PROFILE REMOVE=default`, `CLEAR_PAUSE`, `SDCARD_RESET_FILE`, `SET_FAN_SPEED FAN=pcb_fan SPEED=0`, `SET_GCODE_OFFSET Z=0 MOVE=1`, `G90`, `M82`, `M18`.
4. Completed -> `printCompleted()`, cancelled -> `printCancel()`, error -> G `CANCEL_PRINT` + `printHappendError()`.

### 5.8 Power loss
State is written continuously through `PowerSavingModeFile`/`PrintContinueConfig` (fields: channel `+0x138`, change flag `+0x134`, `+0x140`, line number `+0xe0`, refuelling, clear, saved Z `+0xb8`, E `+0xbc`, targets, fan, file name). On recovery start (`serialPrint` recovery branch, strings "recovery first move x/y/z", "recovery speedCmd"):
1. If a change was in progress (`+0x134`): `printClearGoPos`; `clearAllFilament`; `powerOffUnLoad(chn)` 005f77f0 (F13 poll, `fourInOneUnLoad` on the lane(s) in use, `cutFilament`); `changeChannel(1, savedNewChn, px, py)`.
2. Seek in the file (`getRecoveryPrintSeek` or `seekNumOfRowsOfFile`), G `SET_IDLE_TIMEOUT TIMEOUT=864000`, `setPlatformHeat`, `setRightNozzleTemp` (saved), G `M106 S<fan*255> T0`, wait `waitArriveTemperature(false,true,true)` (1 s poll), `printClearGoPos`, G `G1 Z<savedZ+10> F800` (10.0 at 0x00aeae98), `M400`, `flushFilamentSecond(chn)`, `flushFilamentBrush(true)`, G `G90`, `G1 Y220 F12000`, G `G92 E<savedE>`, `G1 E<savedE-1> F1000`, `G92 E<..>`, `M400`, G `G1 X<x> Y<y> F6000`, `G1 Z<z> F900`, `M400`, G `M220 S<speed>`, G `M106 S<fan*255> T0`, `G90`/`M82|M83` per `absolute_extrude`, `M400`, then the normal start tail (`M21`, `M23`, `M26 S<seek>`, `SDCARD_SET_CHANNEL`, `SDCARD_ENABLE_FFM`, `M24`).

---

## 6. Error codes (UI dialog `E<code>`, `https://wiki.flashforge.com/en/ad5x/error_code_list_ad5x#...`)

| code | raised by | text (wiki anchor) |
|---|---|---|
| E0100..E0103 | `getIFSLoadErrorCode(chn)` from `checkFeeding` (second 30 s timeout), `checkLoad` (second 31 s timeout) | channel 1..4 feeding timeout |
| E0104..E0107 | `getIFSUnLoadErrorCode(chn)` from `doLoadAndUnload` (second cut did not clear the toolhead) | channel 1..4 retracting timeout |
| E0108 | `Filament::slot_operationError` (UI load wizard) | failed to feed filament to the extruder |
| E0109 | `slotIFSMottorNoRunning` 005f369c (IFS odometer roller N not moving; stall/vibr/silk counters, `m_stallCount`) | IFS odometer roller 1/2/3/4 not moving |
| E0110 | only the wiki URL string found | filament type mismatch (no raising code found) |
| E0113 | `sig_extruderSensorAbort` from `checkPrintUnLoad` and `checkFourInOneLoad` | filament detected in the extruder, check feeding position, clean manually or check the sensor |
| E0114 | `checkFourInOneLoad`, `doLoadAndUnload` (state 0x7e more than 100 times / return 10), `Filament::slot_ifsHomeError` | IFS homing error ("IFS home anomaly!" / "IFS home error!") |
| E0116 / E0117 | `checkResponseError` (Klipper messages `Exception in priming_handler` / `Exception in flush_handler`) | exception in priming / flush |
| E0001..E0011, E0017, E0118..E0123 | `checkResponseError` (Klipper shutdown strings, TMC, MCU, heater, timer) | not IFS related |
Shown to the user as `E<code>: <text>`; the "0x7e / 0x7f" values are internal IFS states and are never shown as such. "filament runout" has no dedicated E code: runout leads to the pause with the `autoLoadNoFilamentPause` dialog.

---

## 7. Spool / colour / material data the host keeps (only what drives the above)

- `FFMInfo` section of `Adventurer5M.json`: per channel 1..4 filament type string and colour string (accessors `Config::getFilamentType1..4`, `getFilamentColor1..4`; `getChnFilamentType/Color(chn)`), plus `FFMInfo.channel` (= `Config::getChannel`, the lane currently loaded, default 1, written by `Config::setChannel` after each successful change/auto-detect).
- Slot -> lane map: `this+(slot+0x94)*4` (array at `this+0x250`, slot = tool index in the file), current slot `this+0x248`, loaded lane `this+0x24c`, used-lane mask from the job `this+0x294`, lane-has-filament mask (IFS sensors, F-status) `this+0x298`, IFS present `this+0x2e2`.
- Colour string drives only `getFlushVol` and `autoDetectLoad` (type and colour equality). Type string drives section 2 only. There is no spool weight or remaining-length data in these paths.

---

## 8. Not found / uncertain

- Exact S values of `F10/F11` in places where the decompile hides the literal: all listed above come from the instruction-level literal dump (`S1200` = 0x4b0 everywhere except the unload `S600`/`S<UnloadSpeed>` and flush `S<FristSpeed>`).
- Semantics of IFS commands F15/F23/F39/F112 on the IFS side are from `NOTES.md`/`IFS_MOTOR_SPEC.md`, not re-derived here.
- `checkRefulling*`/`checkLoad` poll thresholds (10/11/31/6) are read from `slti` constants; the exact branch that distinguishes the first vs second timeout in `checkLoad` was inferred from the flow (variable `local_64`), not single-stepped.
- Nozzle temperature policy between old and new filament on a toolchange: not in the host (no M104/M109 on that path); it comes from the sliced G-code. Where the job nozzle temp `Print+0xf0` is parsed from (`Print::initWidget` string scan) was not traced further.
- Fan unit of `this+0x224/0x228` (0..1 vs 0..255) not confirmed: `resumePrintFanControl` multiplies the stored float by 255 for `M106 S`, `changeChannel` writes it raw into `SET_FAN_SPEED SPEED=`, which takes 0..1.
- `getFilamentTypeLoadFristSpace` / `LoadSpace`: no callers found.
- No separate "tip forming", ramming or temperature-drop step exists in the host; the only filament shaping is the cutter, `G1 E-5 F600` after the cut, then `G1 E-60` with the lane retract.
