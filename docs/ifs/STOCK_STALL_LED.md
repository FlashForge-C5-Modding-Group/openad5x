# Stock IFS odometer (stall), host E0109 monitor, LEDs

Sources: the Ghidra decompile of the stock `ifs.bin`, the decompile of `firmwareExe` (`SerialObject::*`, `Print::*`, `Status::*`, `Config::*`) and the IFS initial RAM image. Nothing was run on a printer. "not found" = looked for, absent. "inferred" = from code reading only.

## A. IFS firmware: speed (odometer) sensors

### A1. Sampling (main loop `FUN_08015ea0`, addresses are decompile lines/functions)
- Speed inputs, idx = lane-1: idx0 ADC2 ch7 (PC1, `DAT_080162c4`=0x40020c00), idx1 ADC2 ch9 (PC3), idx2 ADC3 ch5 (PB13, `DAT_080162ec`=0x40021800), idx3 ADC4 ch5 (PB15, `DAT_080162d8`=0x40021c00). Each read is a blocking single conversion `FUN_080110dc(adc, ch)` (`FUN_08010fcc(adc,ch,1,7)`, sample-time code 7).
- Gate: main-pass counter `uVar5` counts passes; when `> 1000` (every 1001st pass) it reads ALL 8 inputs (4 silk + 4 speed) back to back. No gating by selected lane, active lane, feed state or any command: all four lanes are always sampled and always processed.
- Per input a counter runs 1..20: samples 1..20 are summed; on the 21st sample the stored value = sum / 20 (integer, uint16, raw 12-bit counts 0..4095) and the 21st sample itself is discarded, counter restarts. So the stored average `avg[i]` (RAM 0x20000144 + 2*i, F21 "stall:" values) is a new value every 21 x 1001 main passes.
- Time per main pass and ADC conversion time: not found (no measurement, no cycle count done). So the update period of `avg` in ms is unknown; SysTick below samples it every 20 ms regardless, so consecutive SysTick samples are often identical.
- Dead code (no readers): per-lane flags at 0x2000015e/0x20000162 (outside 1397..2636 / <1200 / >2800 tests).

### A2. Movement latch (SysTick 50 Hz = 20 ms, `vec_15` 0x080121b2 -> `FUN_080121bc`)
SysTick reload = SystemCoreClock/50 - 1 (`FUN_08015834`); SystemCoreClock = 144000000 (initial RAM 0x20000488 = 0x08954400), so exactly 20 ms.
Per lane i (independent, same code x4), state `k` = byte 0x2000021c[i], ring `buf` = uint16[50] (0x2000139c, 0x20001400, 0x20001464, 0x200014c8), flag = byte 0x200001d9[i], counter = uint32 0x2000152c[i]:

```
tick(i):
  if k < 50:                      # 0x32
      buf[k] = avg[i]
      d = abs(buf[k] - buf[0])    # compared against the FIRST sample of the window
      if d >= 15:                 # exact: d < 0xf is "quiet"
          flag = 1
          cnt += 1                # if cnt > 0xffffffef after increment -> cnt = 0
          k = 0x31
      elif k == 0x31:             # 49: whole window quiet
          flag = 0
      k += 1
  else:                           # k >= 50
      k = 0                       # this tick takes no sample
```
- Window: baseline buf[0] = avg at k=0; compared every 20 ms against baseline for k=1..49.
- Movement seen (d >= 15 counts): flag = 1, counter + 1, window ends at once: k = 0x31 then +1 = 0x32, next tick resets k = 0 (no sample), the tick after takes the new baseline. Gap between counter increments is therefore >= 3 ticks (60 ms), at most one increment per window.
- Quiet window: flag cleared at the tick where k == 49, i.e. 50 samples after the baseline = 1.00 s; then one extra reset tick, so full quiet cycle = 51 ticks = 1.02 s. "One quiet second" is right: flag = 1 stays until a full window passes with every sample within < 15 counts of its baseline.
- Flag meaning: 1 = filament MOVING (naming "stall" is misleading). Counter = number of movement windows.
- Not gated by lane selection, motor state or any command.
- Counter clear: only the feed state machine (`FUN_0801900c` cases for F10 start: counter[0] in states 10 and 0xe; counters [1] and [2] in the following state pairs; counters [2]/[3] also via `DAT_08019bf8`+8/+0xc; exact state-to-command mapping per lane not re-derived). Flags are never cleared except by the quiet window. Not cleared by F14/F40 reads. RAM init = 0.

### A3. Reply fields
- F13: `F13 ok. FFS_state: %d silk_state: %d chan: %d ffs_channels_insert: %d stall_state: %d jinsi_GCONF: ... qiehuan_GCONF: ...\r\n`. `stall_state` = byte 0x200000da = f[3]<<3 | f[2]<<2 | f[1]<<1 | f[0] from the flags 0x200001d9[0..3] (bit i = lane i+1; 1 = moving). `silk_state` = same from silk flags 0x200001bf (1 = filament present at the lane sensor).
- F14: `F14 ok. stall: a b c d \r\n` raw flags 0/1.
- F40: `F40 ok.stall count: C1: %d C2: %d C3: %d C4: %d \r\n` uint32 counters.
- F21: raw avg arrays (silk first, then speed).
- Stall never changes motor behaviour in the firmware.

## B. Host firmwareExe: E0109

### B1. Feed of data: `SerialObject::recvQueryFourInOneSt` 005fa660 (thread)
- Loop. If `this+0x2f0` (setFourInOneBusy: set during load/unload/cut/feed waits) is set: `sleep(1)`, no F13 sent.
- Else send `F13` via `sendCmdToUart4`. No "ok" in reply: fail counter++; after >= 4 consecutive failures (and having been online before) `sigIfsStatus(false)`; `sleep(1)` between failures.
- Reply tokenised with regex `[: ]`, empty tokens skipped: tok5 = silk_state (-> `iVar5`), tok9 = ffs_channels_insert (-> `iVar8`, used for auto-load), tok11 = stall_state. (tok3 FFS_state, tok13 GCONF are used by `Status::slotSendCmdF13Recv` 007c49b4, which only displays the bits in `Status::updateIfsOdometerStatus` 007c46b4 as per-lane OK/not-OK labels.)
- Only when `MainWindow::getMainMachineStatus() == 5` (print running; set 5 in `Print::delayStartPrint` 0068c4c8 and `Print::homePrintResumeFinish` 006822e4; 0 idle, 2/3 pause, 6 resume click, 9 cancel) it calls `sigIFSMottorNoRunning(stall_state, 0, silk_state)`. The second argument ("vibr") is the constant 0 (never filled).
- Polling period: status 5 (printing) -> `sleep(1)` per loop = one F13 about every 1 s plus the reply time (the IFS also spends ~8 ms in F13 reading both TMCs); status 0 (idle) -> `usleep(200000)` (200 ms); any other status -> `sleep(1)`.
- F14 and F40 are NEVER sent by the host (no string "F14"/"F40" in SerialObject). The only odometer input is the F13 `stall_state` bit mask. F40 counters are not used host-side.

### B2. `SerialObject::slotIFSMottorNoRunning` 005f369c (slot of sigIFSMottorNoRunning, signal index 0x2b; only emitter is recvQueryFourInOneSt 005fac50)
Args: p1 = stall_state mask, p2 = 0, p3 = silk_state mask.
Outer gate, all must hold:
1. `this+0x2e4` != 0: copy of startPrintPthread param 6 (`Print+0x9a`, a per-job flag from the Print dialog ctor param 7; exact meaning not resolved, inferred "this print uses IFS/multicolour").
2. `this+0x2e2` != 0: IFS online (`slotIfsStatus` 005f3bc0 sets it from the F13 poll result).
3. `this+0x98` != 0: this is `Config::getMileageEnable()` read in the SerialObject ctor (005e5608). Config key `OdometerEnable` (JSON, default false, written by `MoreInfo::on_btnMileage_clicked` 005a49d8). Setting is read at construct time; the only other setter is `setIroning` 005defe8 (identical-code-folded name) called from `MachineInfo::on_btnPower_clicked`. So the E0109 monitor is OFF unless OdometerEnable is true.
4. `this+0x2e0` == 0 (m_refulling: toolchange pending/in progress).
5. `this+0xd0` != 0 (IFS filament loaded/active: 1 after `changeChannel` with param_2 == 0 and after a successful pause-resume; 0 at `initPrint` and at `timeOutPause`).
Then: `ch = *(this + (m_channel(+0x248) + 0x94)*4)` = 1-based lane from the tool->lane map at this+0x250 (16 ints, default (i&3)+1); `u = ch - 1`. m_channel (+0x248) comes from Klipper `virtual_sdcard.channel` in `doQueryResponse`.
Inner gate: `(silk_state >> u) & 1` (filament present in that lane) AND `E = this+0xc0 > 0` AND `E != this+0xc4` (last evaluated E).
- `this+0xc0` = gcode_move.gcode_position[3] (E position in mm, absolute) from the `objects/query` reply; updated in `doQueryResponse` only when not refuelling (`+0x2e1`==0) and not paused (`+0x8a`==0) and the position changed. `initPrint` and ctor zero `+0xc0/+0xc4`; `serialPrint` sends `G92 E0` at print start.
Action when the inner gate passes: `+0xc4 = E` (so each new E value is evaluated once), then
- if `(stall_state >> u) & 1 == 0` (lane NOT moving): `m_stallCount[ch]` (int at `this + ch*4 + 0x29c`) += 1; if the new value `> 200` (i.e. 201st evaluation): E0109 fires.
- else (lane moving): `m_stallCount[ch] = 0`.
Counters (16 ints at this+0x2a0..0x2df) are zeroed at the start of `serialPrint` 006042e4 (after `sleep(2)`).
Time estimate: a poll evaluates only when E changed since the previous evaluation. During normal extrusion that is every poll (~1 s), so about 201 s of continuous "E advanced but lane not moving" polls; any poll with the lane flag = 1 resets the count to 0.

### B3. What fires
After count > 200: debug "IFS odometer roller: <u>", then `readM25()` (signal index 0x1b, connected in `Print::Print` to `Print::on_pause_clicked`: the print is PAUSED through the normal UI pause path), then `sigIFSError("E0109: " + tr(...) + number(ch) , wiki URL or empty (URL "https://wiki.flashforge.com/en/ad5x/error_code_list_ad5x#e0109-ifs-odometer-roller-1234-not-moving" when `this+0x1f5` != 0), "E0109")`. `Print::slotIFSError` 006796b8 shows the ErrorDialog and `MainWindow::setErrorCode("E0109")`. The counter for that lane is reset to 0 afterwards. No F-commands are sent, motors are not touched by this path. Message text pieces come from `tr()` calls whose strings were not resolved (wiki text: "IFS odometer roller 1/2/3/4 not moving").

## C. LEDs (IFS firmware)
Pins: GPIOB 0x40010c00. Boot init `FUN_08011b48`: PB5 and PB6 configured output push-pull (config word 0x10030020 / 0x10030040), then `FUN_08011984(GPIOB,0x20)` (write +0x10 = set high) and `FUN_08011980(GPIOB,0x40)` (write +0x14 = clear low).
Complete list of writers (all code searched: every literal-pool reference to 0x40010c00 and the F-command region):
| Event | PB5 (0x20) | PB6 (0x40) | where |
|---|---|---|---|
| Boot | high | low | `FUN_08011b48` from `FUN_080111a0` |
| F15 | high | low | F15 body 0x080134d6 (also FFS_state = 5, reply "F15 ok. ") |
| FFS_state 126 (0x7e), homing failure | low | high | `FUN_0801900c` case 0x7e (also PB1 high); runs on every TIM6 tick (78 us) while the state stays 126 |
| FFS_state 127 (0x7f), all other states, all other commands | unchanged | unchanged | no LED writes |
State 126 is entered only from homing: state 2 (back-off done and PB9 reads 0) or state 3 (seek count >= 0x4000). The ERR pattern stays until F15 or a reset; a later successful homing (F18/F24/driver-reset recovery) does NOT restore it. No blink, no timing, no insert/stall/command indication anywhere.
Which pin is D4 (OK) vs D5 (ERR) and the electrical polarity: not found in the binary or in board/ifs1.jpg (back side, LEDs not visible; no schematic). Pattern consistent with PB5 = OK, PB6 = ERR (inferred, polarity unknown).

## Python model (exact numbers)
```
TICK=0.020; THRESH=15; WIN=50
class Lane:
    k=0; buf=[0]*50; moving=False; count=0
    def tick(self, avg):
        if self.k < WIN:
            self.buf[self.k]=avg
            if abs(avg-self.buf[0]) >= THRESH:
                self.moving=True; self.count=(self.count+1)&0xffffffff
                self.k=0x31
            elif self.k==0x31: self.moving=False
            self.k+=1
        else: self.k=0
# avg: sum of 20 ADC samples //20, refreshed every 21 sample rounds (period not measured)
# stall_state = sum(l.moving<<i); host poll F13 ~1 s while printing
# host: if gate and silk_bit and E>0 and E!=lastE: lastE=E; cnt = cnt+1 if not moving else 0; if cnt>200: pause + E0109, cnt=0
```
