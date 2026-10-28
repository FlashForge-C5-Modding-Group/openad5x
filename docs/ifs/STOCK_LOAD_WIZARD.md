# Stock AD5X touchscreen: filament Load / Unload wizard for an IFS lane

Source: static analysis of `firmwareExe` (Ghidra 12.2 headless, read only, project copy never modified). Addresses are entry points or instruction addresses of the decompile/disassembly. Literals were read from the binary's string data (`ScanRange`/`FuncStr2` dumps in the session scratchpad `re3\`). Not repeated here (see `STOCK_SPEC_HOST.md`): section 3 primitives (`printClearGoPos`, `fourInOneCut`, `checkCrotchCutting`, `checkCrotchF39`, `cutFilament`, flush pieces), section 2 type tables, error table. Wire format `F<cmd> C<chn> L<len> S<speed>`; F13 reply split on `[: ]`, empty tokens skipped: tok3 = FFS_state (5 done, 0x7f error, 0x7e busy/timeout), tok5 = silk_state (lane sensor bitmask, bit n-1 = lane n), tok9 = ffs_channels_insert, tok11 = stall_state (odometer bitmask).

Class fields used by `Filament::` (this): `+0x14` SerialObject, `+0x1c` running flag (cleared by Cancel; every wait loop exits on 0), `+0x28` last lane-sensor mask (tok5), `+0x38` operation (1 load, 2 unload), `+0x40` selected lane (0 = non-IFS right extruder, 1..4 = IFS lane).

## 0. Two different "load" paths

1. Auto-insert (user pushes filament into the lane inlet, lane sensor trips): `SerialObject::checkFourInOneLoad` 005fa288 -> `fourInOneLoadFristStep` 005f839c (`F10 C<n> L650 S1200`, 100 ms polls, max 120 polls) -> `fourInOneLoadSecondStep` 005f7b4c (`F11 C<n> L100 S1200`) -> `F23 C<n>` -> `F39 C<n>`. No heat, no extruder, no G-code. Fully documented in `STOCK_SPEC_HOST.md` 5.1 and `STOCK_HOST_RELEASE.md`; it is "Step A" of the request. While it runs `Filament::checkAutoLoadFilament` 005899c4 blocks the wizard with the dialog "auto loading, please wait..." (and "Please pause the print." if a print is running).
2. Touchscreen wizard "Load" (this file): one button runs everything from heating to purge. Its three on-screen steps are the labels set in `on_buttonLoad_clicked` 00596310 / `on_btnLoad_clicked` 005969f0: **Heating -> Push -> Clear**. Unload labels (`on_buttonunLoad_clicked` 00596520): **Heating -> Cut -> withdraw**. There is no separate "insert to sensor" screen and no "did the filament come out of the nozzle?" confirmation dialog anywhere in `Filament::` (no such string; not found). The only user-facing UI hint is the static text "Select the slot and click feed to load the wire material." (string 00adddc0).

## 1. How the wizard starts

- `on_btnLoad_clicked` 005969f0: `checkAutoLoadFilament()` (abort if auto-load running or print not paused) -> `showEditWidget(false)` (type/colour edit page). `on_buttonLoad_clicked` 00596310: `doEdit()` (writes `FilamentType<n>` / `FilamentColor<n>` for lane n into config via `Config::setFilamentType1..4/Color1..4`), set labels Heating/Push/Clear, `disableButtonItem(false)`, `doFilament()`. Unload: `on_buttonunLoad_clicked` 00596520 same with `+0x38 = 2`.
- `doFilament` 0058c3ec: `+0x1c = 1`, `stepOne` (step icon 1), `MainWindow::setOperationFilament(true)`, if not printing `setMainMachineStatus(1,1)`, `SerialObject::setFourInOneBusy(true)` (silences the status poller), `system("echo 3 > /proc/sys/vm/drop_caches")`, then `createThread(pthreadDoChangeFilament, stack 0x40000)`.
- `pthreadDoChangeFilament` 00595cb0: `+0x38 == 1` -> `doLoad`; `== 2` -> `doUnload`; then `sig_setpThreeFinished` -> `slot_setpThreeFinished` 00591780 / `stepCompelte` 0059145c (cool-down, section 5).
- `doLoad` 00593f58: lane `+0x40 < 1` -> `doIpdLoad` 00591e58 (non-IFS extruder; see 6), else `doFFMLoad` 00593974.

## 2. LOAD, lane to head: `Filament::doFFMLoad` 00593974 (lane n = `+0x40`)

In order:

1. `updateFilamentTemp(n)` 0058b828 -> target (section 3). G `M104 S<target>` (string "M104 S" 00addb9c at 00593a0c; `sendGcodeCmd(...,1,0,0,0)`). M104, not M109, no fan, no bed.
2. If `MainWindow::getHomeCompleted() == 0`: `SerialObject::homeManager(...)` (00593ccc call site). If `+0x1c == 0` return.
3. `printClearGoPos(LeftExtruderXOffset, LeftExtruderYOffset)` 005ed008 -> `G1 X<x+52.5> F12000`, `G1 Y220 F12000`, `G1 Y<y+229> F3000`, `M400` (literals 005ed0bc..005ed238). The head parks at the purge chute while heating.
4. `sig_showCancelBtn`. `checkheating()` 00591a18: loop `sleep(1)`; reads `MainWindow::getNozzleRightRealTemp/TargetTemp`, emits `sig_tempE(real,target)`; **done when `0 < target && target <= real <= target + 19` (0x13)**; returns 0 (abort) if `+0x1c == 0`. No timeout. Target value is the M104 above (read back from Klipper).
5. `sig_setpOneFinished` (UI step 2 "Push"). `SerialObject::setPauseAutoLoad(true)`.
6. Old-filament check, only if `Print::instPrint == 0` or `Config::getFFMEnable() != 0`: `checkFilamentSenser()` (Klipper `GET_FILAMENT_VALUE`, parse "value:" float, 005f1b44) true means filament in the toolhead:
   - `cur = Config::getChannel()` (1 if 0). `cutFilament(cur, x, y)` 005f5e58 (cutter moves, `G92 E0`, IFS `F11 C<cur> L60 S<UnloadSpeed>` + `G1 E-60 F<UnloadSpeed>`, see spec 3.2/3.5). Then `checkUnLoad(cur,false)` (section 2a).
   - result != 0: for lanes 1..4 with bit set in `+0x28` and != cur: `checkUnLoad(lane,true)` until one returns 0. If none: 2 -> `sig_extruderSensorAbort` (E0113 dialog, wizard ends); 10 -> `sig_ifsHomeError` (E0114, "IFS home anomaly!"/"IFS home error!"); other -> `sig_ifsError` (E0108 dialog `slot_operationError` 00589c3c: "Failed to feed filament to the extruder!" + wiki link `...#e0108-failed-to-feed-filament-to-the-extruder`). In practice `checkUnLoad` returns only 0/2/10, so E0108 is reached only through `Filament::emitShowError` 0058a9b4.
   - result 0: `updateCurve3`, `sig_showLine`, continue.
   - sensor empty (or print with FFM disabled): `sig_showLine`, continue.
7. **Lane feed**: `Filament::fourInOneLoadFristStep(n)` 00592534 (section 2b). Then `sig_setpTwoFinished` (UI step 3 "Clear").
8. If it returned 0: `SerialObject::cleanFilamentBox(n, 0, x, y, false)` 005fce9c = the purge (section 2c); G `M400` (00593dbc); `Config::setChannel(n)`. If it returned 2 nothing more happens (no dialog, wizard just ends).

### 2a. `Filament::checkUnLoad(lane, clamp)` 005930b4 (retract the old lane clear of the head)
- if `clamp`: `checkCrotchCutting(lane)` (F24) and IFS `F11 C<lane> L60 S1200` (005931b0, S = 0x4b0).
- G `M400` (00593258). Loop (exits 0 when `+0x1c == 0`): IFS `F13`; state (tok3):
  - 5 and first time: IFS `F11 C<lane> L60 S1200` again (005934c0), mark done; 5 second time: return 2 if `checkFilamentSenser` still true else 0.
  - 0x7f: `F15`, `checkCrotchCutting(lane)`, `F11 C<lane> L100 S1200` (00593690).
  - 0x7e: return 10.
  - `sleep(1)` per turn, no timeout.

### 2b. `Filament::fourInOneLoadFristStep(lane)` 00592534 (lane filament to the toolhead sensor)
1. `checkCrotchCutting(lane)` (F24 C<lane>, polls up to ~21 s, spec 3.3).
2. IFS **`F10 C<lane> L1000 S1200`** (literals "F10 C" 00addbc8, " L1000 S" 00addbd0, S = 0x4b0 = 1200 mm/min = 20 mm/s; call 00592600). No sensor pre-check (the auto path has one).
3. Loop while `+0x1c != 0`: IFS `F13` (00592a38), then
   - tok11 (stall_state) == 0: counter++, **return 2 once the counter exceeds 45 (0x2d)** (odometer shows no movement; counter is never reset).
   - tok3 == 5: leave loop.
   - tok3 == 0x7f: `F15`, `checkCrotchCutting(lane)`, resend **`F10 C<lane> L1500 S1200`** (00592c14, " L1500 S" 00addbf4).
   - `checkFilamentSenser()` true: leave loop.
   - `sleep(1)`.
4. IFS **`F112`** (00592d98). Return 0. (Also reached on Cancel.) No back-off `F11`, no `F23`/`F39` here (those come in the purge).
   Max feed in one go is 1000 mm (50 s at 20 mm/s) or 1500 mm after a recover; there is no time limit other than the 45-poll stall rule.

### 2c. Purge: `cleanFilamentBox(n, 0, x, y, false)` 005fce9c, then `M400`
Sequence (details and literals in `STOCK_SPEC_HOST.md` 3.10; call order verified at 005fcf60..005fd174):
1. G `G1 X<x+52.5> F12000`, `G1 Y<y+229> F3000`, `M400`.
2. `flushFilamentFrist` 005fc930: `M106 S<fan1>`, `G92 E0`, `G1 E90 F<feed1>`, IFS `F10 C<n> L90 S<feed1>` (005fcba4/005fcbb4), `checkLoad(n, feed1)` 005fbaa0 (F13 1 s polls; state 5 + toolhead sensor -> `F112`; `F10 ... L30/L50/L600` recoveries; `F39` after 6 polls; timeouts raise `sigIFSError(E0100+n-1)` "load timeOut!"), `checkCrotchF39(n)`, `M400`, `M106 S<fan2>`.
3. `flushFilamentBrush(false)`: 3 s dwell, three Y wipes `G1 Y220 F12000`/`G1 Y<y+229> F3000`, `G1 X<x+52.5> F12000`, `G1 Y<y+229> F3000`, `M400`.
4. `flushFilamentSecond(n)`: `M106 S<fan1>`, 3 s dwell, `G92 E0`, `G1 E90 F<feed2>`, `M400`, `M106 S<fan2>`.
5. `flushFilamentBrush(true)`: 3 s dwell, `G92 E0`, `G1 E-3 F300`, `M400`, `G92 E0`, wipes.
6. IFS **`F23 C<n>`** (005fd160). Total extruder push 180 mm (2 x `G1 E90`), speeds/fans from the type tables (PLA: F300, fan 0 then 125).
Quirk: the type used for feed/fan is `Config::getChannel()` and in `doFFMLoad` `Config::setChannel(n)` is called AFTER the purge, so the tables use the previously loaded lane's type (00593da4 before 00593e08).

## 3. Nozzle temperature (`Filament::updateFilamentTemp` 0058b828, used by load and unload)
Type string = `Config::getFilamentType<n>()` of the selected lane (case 0..4; set by the edit page). Exact-string compare (decoded from the nested ifs):

| type | M104 S |
|---|---|
| PLA, PLA-CF | 220 (0xdc) |
| SILK | 230 (0xe6) |
| TPU | 250 (0xfa) |
| PA, PC-ABS | 270 (0x10e) |
| PET-CF, PPS-CF, PC | 280 (0x118) |
| PA-CF | 290 (0x122) |
| PAHT-CF | 305 (0x131) |
| anything else (PETG, ABS, ASA, ...) | 230 (0xe6) |

This differs from `getFilamentTypeTemp` (220/230/250, end-of-print purge only).

## 4. UNLOAD wizard: `doUnload` 00595a4c -> `doFFMUnload` 00594f60

`doUnload`: `updateFilamentTemp(n)`; G `M104 S<target>` (00595b14); `homeManager` if not homed (00595bf8); `sig_showCancelBtn`; `checkheating()` (same rule, section 2 step 4); `sig_setpOneFinished` (step 2 "Cut"); lane `n >= 1` -> `doFFMUnload`; lane 0 -> `cutStart` 0058a9c4 + wait up to 12 s for the sensor to clear (non-IFS path, not described further).

`doFFMUnload`:
1. `setPauseAutoLoad(true)`. `Filament::unLoadCut` 0058b2a8 (own copy of the cutter): `M400`, `G90`, `G1 Y10 F18000`, `G1 Y<CutYOffset-7.5> F1800`, `G1 X20  F12000` (two spaces), `G1 X<CutXOffset-2.5> F600`, `M400`, `G92 E0`, `G1 E-5 F600`, `M400` (literals 0058b308..0058b700; offsets as in spec 3.2).
2. `printClearGoPos(LeftExtruderXOffset, LeftExtruderYOffset)`.
3. `haveFil = getE0Filament()` (toolhead sensor reads filament). `lane = haveFil ? Config::getChannel() : selected n`.
4. `checkCrotchCutting(lane)` (F24). G `G92 E0` (waited). G **`G1 E-60 F600`** (005950d4, 600 literal, not waited, `sendGcodeCmd(...,0,...)`: the extruder retract runs in parallel with the lane retract).
5. `Filament::fourInOneUnLoad(lane,false)` 005946b8: IFS **`F11 C<lane> L130 S1200`** (0059479c, " L130 S"), G `M400`, poll `F13` every 1 s: state 5 -> return 0 if the toolhead sensor is clear, or 0 if the lane's sensor bit (tok5) is still set, else 5; 0x7f -> `F15`, `checkCrotchCutting`, resend **`F11 C<lane> L100 S1200`** (00594c9c); 0x7e -> return 10 -> `sig_ifsHomeError` (E0114) and stop. Ends when `+0x1c == 0`.
6. `sig_setpTwoFinished` (step 3 "withdraw"). If the toolhead had filament: `checkCrotchCutting(selected n)` (F24).
7. IFS **`F11 C<n> L1000 S1200`** (0059518c, " L1000 S"; withdraws the selected lane). Poll `F13` every 1 s; stop when state 5 or when the lane's silk bit (tok5 of the reply, stored to `+0x28`) is 0 (lane empty); 0x7f: up to 2 times `F15`, `checkCrotchCutting(n)`, resend `F11 C<n> L1000 S1200`; 0x7e: dialog `E0114: IFS home error!` (`SerialObject::emitShowError`) and stop.
8. `checkCrotchF39(n)` (`F39 C<n>`), IFS **`F112`** (005956c8). Then `stepCompelte`.
No `F23` in this wizard; the IFS is not told to re-select.

## 5. Finish and cool-down (`stepCompelte` 0059145c / `slot_setpThreeFinished` 00591780, runs after load, unload, error and cancel)
- If `Print::instPrint == 0`: G `M106 S0` (0059168c), G `M18` (005916dc, steppers off), `setMainMachineStatus(0,1)`.
- `SerialObject::setNozzleHeat(0)` 005ef978 -> G `M104 S0` (or `M104 S0 T0` when the nozzle reads below -10 C; with the `+0xd0` flag it also clears `+0x185`).
- `setOperationFilament(false)`, `setFourInOneBusy(false)`, buttons re-enabled, `stopFilament(false)` (clears cancel flag), status upload (6 = completed ok if not cancelled), `QTimer::singleShot(5000, delayTime)`.
No fan-down delay, no F39/F23/F112 here.

## 6. Retry, error and cancel branches
- Retry on IFS error: only the 0x7f (home/driver error) loop: `F15`, `F24`, resend the same F10/F11 (L1500 for the lane feed, L100 for retract recoveries, L1000 for withdraw; max 2 resends in the withdraw loop, unlimited in the others). 0x7e returns 10/E0114.
- No automatic retry of the head load itself, no user "filament out?" question. The only repetition is the purge's own `checkLoad` loops (spec 3.9).
- Errors: E0113 (`sig_extruderSensorAbort`, filament still in head after retract; text starts "Material is detected in the extruder, ..."), E0114 (`sig_ifsHomeError`), E0108 (`sig_ifsError` -> `slot_operationError`), `slotIFSError` 0058a520 (QString from `SerialObject::sigIFSError`, E0100+n-1 etc.): ConfirmDialog; and `stopFilament(true)` when not printing (aborts the wizard).
- Cancel: `on_btnCancel_clicked` 0058bcac sets `+0x1c = 0`, `uploadStatusToApp(3,0)`, `stopFilament(true)` (`SerialObject+0x2e3`). Loops exit; lane feed/withdraw send `F112`; `stepCompelte` still runs (M104 S0, M106 S0, M18). A cancel mid-purge returns through the flush functions' own cancel checks.
- `doIpdLoad` 00591e58 (lane 0, non-IFS, for completeness): `M104 S`, home, `printClearGoPos`, `checkheating`, wait for sensor (`getE0Filament`, `sleep(1)`), `M400`, `G92 E0`, `M106 S60`, `G1 E90 F300`, `M106 S255`, sleep, `clear_brush`, `printClearGoPos`, `G92 E0`, `M106 S60`, `G1 E90 F300`, `M106 S255`, sleep, `G92 E0`, `G1 E-3 F300`, `M400`, `clear_brush`, `printClearGoPos`, home.

## 7. Ordered step tables

### 7a. Load lane (auto-insert, "Step A"; not a wizard)
| # | Action | Literal | Wait / end | Source |
|---|---|---|---|---|
| 1 | clamp lane | `F24 C<n>` | F13 poll 1 s, <=21 polls | 005f4f8c |
| 2 | feed to toolhead sensor | `F10 C<n> L650 S1200` | F13 every 100 ms, <=120 polls, until sensor | 005f839c |
| 3 | stop | `F112` | | 005f839c |
| 4 | back off | `F11 C<n> L100 S1200` | F13 200 ms until state 5 | 005f7b4c |
| 5 | select / release | `F23 C<n>`, `F39 C<n>` | F13 1 s, <=11 polls | 005fa288 |

### 7b. Load head (UI wizard Heating / Push / Clear)
| # | Action | Literal | Wait / end | Source |
|---|---|---|---|---|
| 1 | heat | `M104 S<table>` (220 PLA ... 305) | none | 00593a0c |
| 2 | home if needed | homeManager | | 00593ccc |
| 3 | park at chute | `G1 X<x+52.5> F12000`, `G1 Y220 F12000`, `G1 Y<y+229> F3000`, `M400` | | 005ed008 |
| 4 | wait temp | | 1 s poll until target <= real <= target+19, no timeout | 00591a18 |
| 5 | old filament in head? | `GET_FILAMENT_VALUE` | | 005f1b44 |
| 5a | cut + retract old | cutter G-code, `G92 E0`, `F11 C<cur> L60 S<spd>`, `G1 E-60 F<spd>`; `checkUnLoad`: `F11 C<cur> L60 S1200` (x1 more), recover `F15`+`F24`+`F11 ... L100 S1200` | 1 s F13 polls | 005f5e58, 005930b4 |
| 6 | clamp + feed | `F24 C<n>`, `F10 C<n> L1000 S1200` (recover `F15`, `F24`, `F10 C<n> L1500 S1200`) | F13 1 s; ends at state 5, sensor true, or cancel; stall_state==0 for 46 polls -> abort (no purge) | 00592534 |
| 7 | stop | `F112` | | 00592d98 |
| 8 | purge | `G1 X<x+52.5> F12000`, `G1 Y<y+229> F3000`, `M400`; `M106 S<f1>`, `G92 E0`, `G1 E90 F<feed1>` + `F10 C<n> L90 S<feed1>`, `checkLoad`, `F39 C<n>`, `M400`, `M106 S<f2>`; brush; `M106 S<f1>`, 3 s, `G92 E0`, `G1 E90 F<feed2>`, `M400`, `M106 S<f2>`; brush with `G1 E-3 F300`; `F23 C<n>` | see spec 3.10 | 005fce9c |
| 9 | `M400`; `Config::setChannel(n)` | | | 00593dbc |
| 10 | finish | `M106 S0`, `M18`, `M104 S0` | | 0059145c |

### 7c. Unload (Heating / Cut / withdraw)
| # | Action | Literal | Wait / end | Source |
|---|---|---|---|---|
| 1 | heat | `M104 S<table>`, home if needed, wait target..target+19 | 1 s poll | 00595b14 |
| 2 | cut | `M400`, `G90`, `G1 Y10 F18000`, `G1 Y<CutY-7.5> F1800`, `G1 X20  F12000`, `G1 X<CutX-2.5> F600`, `M400`, `G92 E0`, `G1 E-5 F600`, `M400` | | 0058b2a8 |
| 3 | park | `printClearGoPos` | | 00594fe0 |
| 4 | retract | `F24 C<lane>`, `G92 E0`, `G1 E-60 F600` (no wait), `F11 C<lane> L130 S1200`, `M400` | F13 1 s until state 5 (sensor clear or lane bit set); 0x7f: `F15`,`F24`,`F11 C<lane> L100 S1200`; 0x7e: E0114 | 005946b8 |
| 5 | withdraw | `F24 C<n>` (if head had filament), `F11 C<n> L1000 S1200` | F13 1 s until state 5 or lane bit clear; 0x7f: <=2 x (`F15`,`F24`,resend); 0x7e: E0114 | 00594f60 |
| 6 | release | `F39 C<n>`, `F112` | | 005956b0, 005956c8 |
| 7 | finish | `M106 S0`, `M18`, `M104 S0` | | 0059145c |

## 8. Not found
- Any "did the filament come out?" prompt / retry loop in `Filament::`: not found.
- Heating wait timeout: none (waits until the cancel flag).
- Exact F-suffix literal of the X move inside `cleanFilamentBox` (the " F12000" string is not resolved separately in the scan; taken from spec 3.10, which was read from the same function earlier).
- Feed/fan numbers for `<spd>`, `<f1>`, `<f2>`, `<feed1>`, `<feed2>`: table-driven, see `STOCK_SPEC_HOST.md` section 2.
- What F13 tok11 == 0 for 46 polls looks like on a healthy printer (assumed: lane not turning; the abort path shows no dialog).
