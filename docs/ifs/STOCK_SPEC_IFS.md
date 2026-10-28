# Stock AD5X IFS firmware 3.0.7: behaviour spec

Source: `ifs.bin` (41168 B, base 0x08010000, N32G455), `ifs.c` decompile, a Ghidra headless run on a COPY of the project (jump-table case bodies at 0x08012e3e decompiled and the whole app disassembled with literal pools resolved), `ram_init.bin`, NOTES.md, STOCK_MOTOR_DRIVE.md, STOCK_HOST_RELEASE.md. Nothing was run on the printer. "not found" = looked for, absent. "inferred" = from code reading, not observed on hardware. Motor register init (TMC writes, EN, planner constants) is in STOCK_MOTOR_DRIVE.md and is not repeated.

Addresses `FUN_xxxxxxxx` are Ghidra names of the function entry. RAM addresses are 0x2000xxxx.

## 0. Architecture

| Item | Value |
|---|---|
| Main loop | `FUN_08015ea0` (called from Reset via `thunk_FUN_08015ea0` 0x080101a0). Runs forever: ADC sampling every 1001st pass, then `FUN_08017ad4` (line parse + driver-reset handler) |
| TIM6 ISR (`vec_70` 0x080124f8, `0x40001000`, 144 MHz/72/156 = 12820 Hz) | calls the FFS_state machine `FUN_0801900c` once per tick (78 us) |
| TIM5 ISR (`vec_66` 0x080124d8, `0x40000c00`, 2 kHz) | feed planner tick `FUN_0801813c` |
| SysTick (`vec_15` 0x080121b2 -> `FUN_080121bc`) | reload = SystemCoreClock/50 - 1 (`FUN_08015834`): 50 Hz = 20 ms at 144 MHz. Speed-sensor movement latch (section 3.3) |
| USART1 IDLE ISR (`vec_53` 0x08012824) | host RX, DMA 200-byte buffer 0x20000ea4 |
| USART2 IDLE ISR (`vec_54` 0x080128a8), UART7 IDLE ISR (vector 91, `FUN_080126d0`) | TMC UART replies (feed = USART2, selector = UART7) |
| DMA1 ch (vec_30 0x080111ec) | USART1 TX complete: clears TX-busy 0x20000106, PA11 low (receive) |
| Watchdog | not found (no IWDG/WWDG address in the literal pools) |
| FFS_state | byte 0x200001b0, reset value 0 |
| Selector position counter | int 0x200001e0 (steps from home) |
| Selector target slot | 0x2000021b (0 = none/neutral, 1-4) |
| Last channel (`chan` in F13) | 0x200000f0, written by F10, F11, F23, F24, F39 (even for invalid values) |
| Selector DIR flag | 0x2000021a (1 = positive) |
| Selector step phase | 0x200001e4 (0/1) |
| Driver-reset request / "needs ack" | 0x20000260 / 0x20000098 |
| Feed params | F10: L 0x200000e4, S 0x200000ec (float, defaults 0 / 600.0). F11: L 0x200000e0 (stored negated), S 0x200000e8 (default 600.0, default L 0). F30: D 0x200000dc int (default 0x800) |

## 1. Serial protocol

### 1.1 Link (host side `/dev/ttyS4`)
- USART1 PA9/PA10, 115200, word length 8, 1 stop, no parity (`FUN_080142b4`: baud 0x1c200, other fields 0, mode 0x0c). RS485 direction PA11: high = transmit, low = receive (idle low).
- Flashing (bootloader) uses 8E1 per NOTES, the app link is 8N1 here.

### 1.2 Receive path (framing)
1. `vec_53` fires on USART IDLE (flag 0x424). It reads the DMA remaining count, n = 200 - remaining. **If n < 3 the burst is discarded** (buffer cleared, nothing queued). Otherwise each byte is pushed to the 200-byte ring buffer (0x20005de4, `FUN_080149b0`), the DMA buffer is cleared (`FUN_08010202`) and re-armed for 200 bytes.
   - So a lone `0xFF` (or any 1-2 byte burst, such as a bare `\r\n`) is dropped. There is no special `0xFF` code anywhere; the host's `0xFF` after the command is only dropped by this length rule (host side purpose, RS485 turnaround, inferred).
   - A burst of 3+ bytes that contains `0xFF` passes the `0xFF` through as an ordinary character; it does no harm because the parser searches for `F`.
2. Line assembler `FUN_08015c54` (called every main pass), one char at a time from the ring:
   - If a complete line is pending (flag 0x200000b9 = 1) it stops reading (one line buffered).
   - Terminator `'\n'` or `'\r'`, or buffer count > 0x5e (94).
   - Terminator with count 0: ignored; clears the "comment" flag 0x200000c8.
   - `';'` sets the comment flag; characters after it are not stored. A line that had a `;` is therefore NOT executed (flag stays set until an empty terminator clears it).
   - Else the char is stored at 0x20000d1c[count++]. On terminator with count > 0: NUL-terminate, set 0x200000b9 = 1 (if not comment), count = 0.
3. Main loop `FUN_08017ad4`: if 0x200000b9 set, call parser `FUN_08012de8`, clear the flag (parser always returns 1).

### 1.3 Parser `FUN_08012de8`
- `strchr(line,'F')` (first uppercase F anywhere; no F = line silently ignored, no reply). Number n = `atof(p+1)` truncated to int (`FUN_08014908` = atof, `FUN_08010564` = double->int).
- Arguments: `strchr(line, letter)` for the FIRST occurrence of that uppercase letter anywhere in the line, `atof` of what follows. Letters: `C` channel (cast to byte), `L` length (float), `S` speed (float, mm/min; planner divides by 60.0 = 0x42700000), `D` (F30, int), `T` and `I` (F42). Case sensitive. Parameters are parsed (and stored) BEFORE the validity checks, so a rejected command still overwrites L/S/chan.
- Dispatch: n == 40 -> F40; n < 41: index n-10 into the halfword `tbh` table at 0x08012e3e (n-10 > 29, i.e. n < 10 or 40+ not handled, returns silently); 41-52 `switch(n-41)`; 53, 54, 60-64, 112 explicit; everything else returns with NO reply.
- Reply: sprintf into a stack buffer, then `FUN_08019e50`: **if TX-busy flag 0x20000106 is 0** (previous reply finished), PA11 high, `sprintf("%s")` into 0x200011c8, strlen (low 8 bits), DMA TX (`FUN_08015bac` sets busy 1). If a previous reply is still being sent the new reply is dropped. The DMA TX-complete ISR drops PA11 low and clears busy. Replies are sent immediately when the command is parsed (motion is not waited for).
- Every reply string below is exact, including spaces. `<CRLF>` = `\r\n`.

### 1.4 Jump table (0x08012e3e, 30 halfwords; targets)
F10 0x08012ed8, F11 0x08013040, F12 0x080131b0, F13 0x080133fc, F14 0x080134a8, F15 0x080134d6, F18 0x080134fe, F19 0x08013516, F20 0x08013528, F21 0x0801353a, F22 0x0801357e, F23 0x08013594, F24 0x0801366a, F30 0x08013738, F37 0x0801378a, F39 0x08013a00. F16, F17, F25-F29, F31-F36, F38 all -> 0x080141a4 = return, **no reply**.

### 1.5 Command list and replies

| Cmd | Behaviour | Reply |
|---|---|---|
| F10 | Feed. Parse L -> 0xe4, S -> 0xec. No `C` present: `F10 ok. No channel selected. <sp><CRLF>`. Else chan = (byte)C -> 0xf0. If FFS_state != 5: `F10 ok. FFS not ready. `. State 5: C=1 -> state 10, C=2 -> 0x15, C=3 -> 0x20, C=4 -> 0x2b, reply `F10 ok. FFS channel N feeding. `; other C: `F10 ok. FFS channel not exist. ` | every reply ends with space + `\r\n`, e.g. `F10 ok. FFS channel 1 feeding. \r\n` |
| F11 | Unload. Same as F10 but L stored NEGATED in 0xe0, S in 0xe8, states C=1 -> 0x0e, 2 -> 0x19, 3 -> 0x24, 4 -> 0x2f; text `F11 ok. FFS channel N exiting. `, `F11 ok. FFS channel not exist. `, `F11 ok. FFS not ready. `, `F11 ok. No channel selected. ` | same pattern |
| F12 | silk flags 0x200001bf[0..3] | `F12 ok. %d %d %d %d\n \r` (note the literal order `\n`, space, `\r`) |
| F13 | First sends a GCONF read (reg 0) to USART2 then UART7 (blocking ~4 bytes at 9600 each, about 8 ms in total), then prints (reply values are the replies from the PREVIOUS read, current ones arrive after) | `F13 ok. FFS_state: %d silk_state: %d chan: %d ffs_channels_insert: %d stall_state: %d jinsi_GCONF: %02x%02x%02x%02x qiehuan_GCONF: %02x%02x%02x%02x\r\n` (no space before CRLF). silk_state = byte 0x200000d9 = f[3]<<3\|f[2]<<2\|f[1]<<1\|f[0] of 0x200001bf; stall_state = byte 0x200000da built the same from 0x200001d9; chan = 0x200000f0; insert = 0x200001d0; jinsi = 0x20000224 bytes 0..3 (feed TMC, USART2), qiehuan = 0x20000238 (selector TMC, UART7). GCONF bytes print MSB first (an intact driver prints `000001dc`) |
| F14 | stall flags 0x200001d9[0..3] | `F14 ok. stall: %d %d %d %d <CRLF>` (`F14 ok. stall: a b c d \r\n`) |
| F15 | PB5 high, PB6 low, FFS_state = 5. Does NOT clear 0x20000098 | `F15 ok. \r\n` |
| F18 | FFS_state = 1 (start homing, see 2). No check of current state | `F18 ok \r\n` (no period) |
| F19 | version | `F19 ok. four color. version: 3.0.7 \r\n` |
| F20 | nothing | `F20 ok. \r\n` |
| F21 | silk ADC averages 0x20000134[0..3] (uint16, raw 12-bit), then speed ADC averages 0x20000144[0..3] | `F21 ok. \r\n silk: %d %d %d %d \r\n stall: %d %d %d %d \r\n` |
| F22 | insert mask byte 0x200001d0 | `F22 ok. ffs_channels_insert: %d \r\n` |
| F23 | no `C`: `F23 ok. no chan. `. C=1..4: clears bit (C-1) of 0x200001d0, reply `F23 ok. chan N. ` ; other C: `F23 ok. no chan. `. Never moves anything | `...\r\n` with space before |
| F24 | no `C`: `F24 ok. No channel selected. `. C=1..4: target 0x2000021b = C, FFS_state = 1 (always re-homes, then goes to the slot), reply `F24 ok. chan N. `. Other C: `F24 ok. FFS channel not exist. ` (state unchanged). **No state check** (works from any state) | |
| F30 | only if `D` present: 0x200000dc = (int)D, FFS_state = 0x80 (manual move, see 2.6). No state check | always `F30 ok. \r\n` |
| F37 | enter bootloader (section 4). No reply | none |
| F39 | no `C`: `F39 ok. No channel selected. `. C=1..4: FFS_state = 0x0c / 0x17 / 0x22 / 0x2d (move to neutral after slot N, no homing), reply `F39 ok. FFS channel N release. `. Else `F39 ok. FFS channel not exist. ` **No state check** | |
| F40 | stall counters 0x2000152c[0..3] (uint32) | `F40 ok.stall count: C1: %d C2: %d C3: %d C4: %d \r\n` |
| F41 / F50 | GCONF read request to feed TMC (USART2), prints 0x20000224 | `F41 ok.GCONF: %02x%02x%02x%02x \r\n` / `F50 ok.GCONF: ...` |
| F42 | `T`<1 or 2> motor (0xf1), `I` irun (0xf2; 0 stays 0, >30 -> 31). T=1: USART2 reg 0x10 = I<<8 \| 0xa0000; T=2: UART7. T missing/other: nothing written | `F42 ok.stepper_motor: %d stepper_motor_irun: %d \r\n` |
| F43 | re-run the full TMC init on both drivers (blocking) | `F43 ok. \r\n` |
| F44 / F53 | DRV_STATUS (0x6f) feed, buffer 0x20000220 | `F44 ok.DRV_STATUS: %02x%02x%02x%02x \r\n`, `F53 ok.DRV_STATUS: ...` |
| F45 / F51 | GSTAT (1) feed, 0x20000228 | `F45 ok.GSTAT: ...`, `F51 ok.GSTAT: ...` |
| F52 | CHOPCONF (0x6c) feed, 0x2000022c | `F52 ok.CHOPCONF: ...` |
| F54 | PWMCONF (0x70) feed, 0x20000230 | `F54 ok.PWMCONF: ...` |
| F60-F64 | GCONF, GSTAT, CHOPCONF, DRV_STATUS, PWMCONF of the SELECTOR TMC (UART7); buffers 0x20000238, 23c, 240, 234, 244 | `F60 ok.GCONF: ...`, `F61 ok.GSTAT: `, `F62 ok.CHOPCONF: `, `F63 ok.DRV_STATUS: `, `F64 ok.PWMCONF: ` |
| F112 | If 0x20000098 == 0: planner reset + PA5 high + PB1 high (both motors off) + FFS_state = 5, reply `F112 ok. yes.\r\n`. Else (0x20000098 = 1, i.e. between a driver-reset event and the post-homing 0x7f) nothing changes, reply `F112 ok. error.\r\n` | no space before CRLF |
| F46-F49, F55-F59, F65-F111, F113+, F0-F9 | no reply | |

All TMC register reads in F41-F64 only SEND the read; the printed value is the last reply received (stale by one call, zero until the first reply). All the reply strings above for F40-F64 follow the same `ok.` (no space after the dot) pattern except F42 whose text is exactly `stepper_motor: %d stepper_motor_irun: %d `.

## 2. FFS_state machine (`FUN_0801900c`, run each TIM6 tick, 78 us)

### 2.1 Meaning of the state numbers
| State (dec / hex) | Meaning |
|---|---|
| 0 | power-up value. Does nothing. Selector NOT homed. F10/F11 reply "not ready" |
| 1 | homing start |
| 2 | homing back-off (sensor was active at start) |
| 3 | homing forward seek |
| 4 | homed, dispatch to target slot |
| 5 | idle / ready (only state in which F10/F11 are accepted). 6: also no-op (unused) |
| 7 | move to slot 1 (count 0); 8, 9 settle, then 5 |
| 12 (0x0c) | move to neutral at count 2048 (also used for target 0); 13 -> 5 |
| 18 (0x12) / 19, 20 | move to slot 2 (4096) |
| 23 (0x17) / 24 | move to neutral 6144 |
| 29 (0x1d) / 30, 31 | move to slot 3 (8192) |
| 34 (0x22) / 35 | move to neutral 10240 |
| 40 (0x28) / 41, 42 | move to slot 4 (12288) |
| 45 (0x2d) / 46 | move to neutral 14336 |
| **F10 feeding** ch1: 10 (start, one tick) then **11** (waiting); ch2: 21 then **22**; ch3: 32 then **33**; ch4: 43 then **44**. When the planner queue empties: ch1 -> 13, ch2 -> 24, ch3 -> 35, ch4 -> 46, each -> 5 next tick. Motor enable stays on |
| **F11 unloading** ch1: 14 (start), 15 (wait), 16 (stop); ch2: 25, 26, 27; ch3: 36, 37, 38; ch4: 47, 48, 49. State "stop" calls `FUN_08015d28` (planner reset, PA5 high, PB1 high) then 5 |
| 101-120 (0x65-0x78), 121-125 | set 0x200001d5[i] = 1 or nothing. No code writes these states: dead |
| 126 (0x7e) | homing error: PB1 high, PB6 high, PB5 low (repeated each tick) |
| 127 (0x7f) | "driver was reset, re-homed" marker: set at the end of homing when 0x20000098 = 1 (clears it); stays 127 until the host sends F15, F18, F24 or F112 (the stock host sends F15, then repeats the F10/F11) |
| 128 (0x80) / 129 (0x81) | F30 manual move; 129 is terminal (never returns to 5 by itself) |

The user's guess is confirmed: 11 / 22 / 33 / 44 are the "feeding, waiting for the move to finish" states for channels 1..4. Host feed completion = state back to 5.

### 2.2 Feed F10 (states 10/11 and siblings)
- Start state: clears stall counter of that channel (0x2000152c[ch-1] = 0), 0x20000158 = 0, calls `FUN_080163bc(L, S)`: queues ONE move of L mm (sign = direction) at S/60 mm/s on axis 0 (feed motor PA0/PA1/PA5), 343.696 steps/mm, trapezoid planner, accel/min rate in STOCK_MOTOR_DRIVE.md section 3. Then wait state: `(wr - rd) & 0x7f == 0` of the planner block queue (`FUN_08016374`) -> finished. The planner ramps automatically (Marlin-like trapezoid); there is no extra ramp or final stop code in the F10 path. EN (PA5) is left low (motor energised, IHOLD=0), only F112 / F11 end / driver-reset stop release it.
- The selector is NOT touched by F10/F11: the host must have clamped the channel with F24 first. F10 does not verify the selected channel against C (it feeds whatever lane is clamped).
- No retry, no stall detection, no timeout in the firmware. L=0 finishes immediately.

### 2.3 Unload F11
Same, with L negated (the move goes backwards), and ending in the stop state (`FUN_08015d28`: planner reset + PA5 high + PB1 high, so the selector motor is also released) then state 5. Host retries (F11 C<n> L70 ...) are host logic (STOCK_HOST_RELEASE.md).

### 2.4 Mid-operation changes
- F24, F39, F18, F30 and F15 have no state check: they overwrite FFS_state immediately. The feed planner is NOT reset by them (TIM5 keeps stepping the queued move until it ends, EN stays low) and the abandoned feed state never reaches its stop state. Only F112 (when 0x20000098 = 0) or the driver-reset handler resets the planner.
- F10/F11 while state != 5: refused with "FFS not ready" and no state change.
- F24 while moving the selector: restarts at state 1 (re-homes from wherever it is).

### 2.5 Selector moves (positions)
8 microsteps, one step = STEP (PA7) low tick then high tick; position counter changes on the rising tick; **6410 steps/s = 140.86 deg/s constant, no ramp**. 16384 counts = 360 degrees (2048 full steps).

| Target | State | Count | Angle |
|---|---|---|---|
| slot 1 (home sensor edge) | 7 | 0 | 0 |
| neutral after slot 1 (target 0, F39 C1) | 0x0c | 2048 | 45 |
| slot 2 | 0x12 | 4096 | 90 |
| neutral (F39 C2) | 0x17 | 6144 | 135 |
| slot 3 | 0x1d | 8192 | 180 |
| neutral (F39 C3) | 0x22 | 10240 | 225 |
| slot 4 | 0x28 | 12288 | 270 |
| neutral (F39 C4) | 0x2d | 14336 | 315 |

Per tick in a move state: PB1 (EN) low (enabled). If count == target: PB1 high (EN off), go to the settle states (each one tick, then 5). Else alternate: low phase = PA7 low; high phase = PA7 high and, if count < target: PA6 (DIR) high, flag 0x2000021a = 1, count++; else PA6 low, flag 0, count--. Move takes the shortest direct count difference (no wrap-around, never the long way).
The arrival check happens on every tick, so the motor is off (PB1 high) as soon as it arrives. Motor off while parked: the slot is held mechanically (the follower sits in a cam detent), IHOLD=0.

### 2.6 Homing (the "start up thing")
Power-up does **not** home: state 0 at boot, nothing in `FUN_080111a0` or main starts it. Homing begins only on F18, F24, or the driver-reset handler (2.8). In the stock host flow the first F18/F24 must be sent by firmwareExe; "who sends it at printer start" is not in this binary, and F18 was not found in STOCK_HOST_RELEASE.md (host side not examined by me).
Home sensor: PB9 (GPIOB 0x200), input pull-up, **0 = triggered**.
1. State 1: read PB9. Triggered (0): PA6 low, flag 0, count 0, state 2, PB1 low. Not triggered: PA6 high, flag 1, count 0, state 3, PB1 low. (Both: one tick.)
2. State 2 (back off): runs exactly **4096 steps (count > 0xfff)** in the negative direction (does NOT stop when the sensor clears). Then count = 0 and re-read PB9: still triggered -> state 0x7e (error); else PA6 high, flag 1, state 3.
3. State 3 (forward seek, DIR high): checked on every STEP-low phase: stop when PB9 == 0 or count > 0x3fff. If count < 0x4000 -> state 4, else state 0x7e. count = 0.
4. State 4: count = 0, 0x200001e8 = 0, PB1 high. If 0x20000098 == 1 -> PB1 high, FFS_state = 0x7f, 0x20000098 = 0 (slot move skipped). Else dispatch on target 0x2000021b: 0 -> 0x0c, 1 -> 7 (and target cleared), 2 -> 0x12, 3 -> 0x1d, 4 -> 0x28; the target is cleared to 0 when 1-4 is consumed (F18 afterwards goes to neutral).
Worst case ~ 4096 + 16384 steps = 3.2 s. So F18 at power-up = find slot 1 edge, then move to neutral 2048 counts, state 5. F24 C1 = find the edge, stop there, motor off.
A failed homing leaves state 0x7e (126) with 0x20000098 unchanged (if it was set it stays 1, so F112 keeps answering "error"; F15 or a new F18/F24 recover).

### 2.7 F30 manual move
F30 D<n> sets state 0x80: PB1 low, state 0x81: moves from the current count to n (absolute count, positive up to any int; no limit, no homing), PB1 high on arrival, stays in state 129. Position counter keeps its value.

### 2.8 Autonomous driver-reset handler (`FUN_08017ad4`)
Both TMC reply ISRs compare the GCONF reply low byte with 0xdc. A mismatch sets 0x20000260. Next main pass: planner reset + PA5 high + PB1 high (`FUN_08015d28`), re-write the TMC init to BOTH drivers (`FUN_08011bc8`), FFS_state = 1 (re-home), 0x20000098 = 1, flag cleared. Result: homing runs and ends in FFS_state 0x7f (127) with the selector parked at home (slot 1, off), until the host does F15/F112. Only triggers when a GCONF read is answered (F13 / F41 / F50 / F60 requests); no periodic polling in the firmware.

## 3. Sensors

### 3.1 Sampling
Main loop counter reaches 1001 then one blocking ADC conversion per input (`FUN_080110dc(adc, channel)`) is taken. Every input keeps a counter of 1..20 accumulated samples; on the 21st sample the average (sum/20) is stored and the counter restarts (the 21st sample is discarded). Conversion time and main-pass period were not measured (not found), so the averaging period is "21 x 1001 main passes".
Inputs (idx = slot-1): silk idx0 ADC2 ch6 (PC0), idx1 ADC2 ch8 (PC2), idx2 ADC4 ch3 (PB12), idx3 ADC4 ch4 (PB14); speed idx0 ADC2 ch7 (PC1), idx1 ADC2 ch9 (PC3), idx2 ADC3 ch5 (PB13), idx3 ADC4 ch5 (PB15). The connector number to slot assumption is from NOTES (to verify).

### 3.2 Silk (filament present) per channel, flags 0x200001bf[i] (reset value 1,1,1,1), averages 0x20000134[i]
- avg < 900 or avg > 3100 -> flag = 1. On a 0 -> 1 change the insert bit is set: 0x200001d0 \|= 1<<i.
- 1001 <= avg <= 2999 -> flag = 0 and the insert bit i is cleared.
- 900..1000 and 3000..3100: hold (hysteresis, no change).
- F23 C<n> clears bit n-1 only; it re-arms only after the flag has gone 0 and returned to 1 (or it never was set).
- At boot the flags are 1: a lane already loaded at power-up creates no insert bit; an empty lane clears its flag after the first average.
- silk_state (F13) and F12 use the same flags, bit i = slot i+1 (F13 only).
- Nothing in the firmware reads these flags to act (readers: F12, F13, ADC loop only). No auto load, no LED pattern on insert.

### 3.3 Speed (movement) sensors and stall_state
- Raw averages 0x20000144[i] (uint16).
- Flags 0x2000015e[i] and event latch 0x20000162[i] in the ADC loop (thresholds: outside 1397..2636, asserted when < 1200 or > 2800, cleared inside 1397..2636) have no readers: dead code.
- The live "stall" data comes from SysTick (every 20 ms, per channel idx): index k = 0x2000021c[i] (byte); if k < 50: buf[k] = avg[i] (50-sample ring per channel: 0x2000139c, 0x20001400, 0x20001464, 0x200014c8); d = |buf[k] - buf[0]|; if d >= 15: **stall flag 0x200001d9[i] = 1**, counter 0x2000152c[i]++ (wraps to 0 above 0xffffffef), k = 0x31 (then k++ -> 0x32, next tick k = 0, i.e. a new window); else (d < 15) and k == 0x31 (50 samples = 1 s with no change >= 15 counts): flag = 0. k++ each tick. When k >= 50: k = 0.
- So the bit named "stall" is 1 when the speed-sensor ADC average moved by 15 or more counts inside the last window (filament MOVING) and returns to 0 after one quiet second. The counter F40 counts these movement windows. Counter i is cleared when an F10/F11 for channel i starts. (Name/meaning for the host: inferred from the code. How firmwareExe uses it is host side.)
- F14 = flags, F13 stall_state = bits (bit i = slot i+1), F21 "stall:" = the raw speed averages (not flags), F40 = counters.
- Stall never stops or changes the motors.

### 3.4 LEDs / PB5, PB6
PB5 high, PB6 low at boot (`FUN_08011b48`) and on F15. State 0x7e: PB5 low, PB6 high. No other writers found. Which of D4 (OK) / D5 (ERR) is PB5 / PB6 is not found in the binary (board photo not read); the pattern is consistent with PB5 = OK, PB6 = ERR (inferred).

## 4. Boot, bootloader, F37
Reset (`Reset_Handler` 0x080101ac) -> SystemInit `FUN_08012428` (HSE, PLL, 144 MHz, flash wait states, VTOR written) -> `__main` (RAM init decompress `0x08010f44`, 0x490 B to 0x20000000) -> `FUN_08015ea0`:
1. VTOR = 0x08010000 (`FUN_08011ba4`).
2. `FUN_080111a0`: NVIC priority grouping 0x700; USART1 115200 + DMA RX 200 B + IDLE IRQ (`FUN_080142b4`, `FUN_08012d20`); ring buffer init `FUN_08017b30`; ADC init `FUN_08011a2c`; UART7/USART2 9600 + DMA (`FUN_080143e4`, `FUN_08012be4`); TMC init writes on USART2 and UART7 (`FUN_08011bc8`, values in STOCK_MOTOR_DRIVE.md); PB5 high, PB6 low (`FUN_08011b48`); 0x20000100 = 0; start TIM5/TIM6/SysTick (`FUN_08015e60`).
3. `FUN_080164a4` (motor outputs off, planner reset), then the main loop.
No delays, no homing, no self test, no reply sent at boot. FFS_state = 0.

F37 (0x0801378a): `FUN_08011fe0(0x0800D000, 0xFFFFFFFF)` = unlock flash, clear status 0x35, erase the page 0x0800D000, program word 0xFFFFFFFF, lock; then FAULTMASK set, DSB, `SCB->AIRCR = 0x05FA0004 | (AIRCR & 0x700)`, loop. No reply. The bootloader (0x08000000-0x0800FFFF) is not in this file; it sees the erased flag word and waits for the upload. Bootloader protocol (XMODEM-like, 115200 8E1, `C` sync, 1030-byte frames, CRC16 0x1021, ACK 0x06 / NAK 0x15, EOT 0x04, written from 0x08010000, only listens right after power-up or the flag state) is from NOTES.md/IFSCommand (not re-derived here). How the bootloader validates the app (SP check etc.) is not found.

## 5. Things the firmware does without host commands
Everything else in the app is passive:
1. ADC sampling (silk flags, insert bits, speed averages).
2. SysTick movement/stall latch and counters.
3. Driver-reset recovery (2.8), only after a host-initiated GCONF read shows a changed GCONF.
4. State-machine progress in TIM6 (settle states, planner-empty detection, F11 stop).
No replies are ever sent unasked, no periodic TMC polling, no watchdog, no timeouts, no auto-load on insert, no stall response, no idle motor release (F10 leaves the feed enabled until F112; F11 end releases both).

## 6. Not found / unverified
- Time per main-loop pass and ADC conversion (so sensor averaging period in ms).
- Which host command first homes the selector at printer start.
- Bootloader internals beyond F37 and the NOTES protocol.
- Physical meaning of D4/D5 vs PB5/PB6.
- Planner block splitting limits for very long L (the F10 L1000 used by the host is accepted by the host flow; exact limits not analysed).
