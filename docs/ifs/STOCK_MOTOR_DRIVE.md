# Stock IFS motor drive vs our Kalico config (feed overheat check)

Sources: the Ghidra decompile of the stock `ifs.bin` (base 0x08010000) and its initial RAM image, and kalico-ad5x `klippy/extras/tmc2209.py`, `tmc2130.py`, `tmc.py`. Nothing was run against the printer.

## 1. TMC register writes (stock)

Writer: `FUN_08019d1e(uart, reg, val)` (sync 0x05, addr 0, reg|0x80, CRC8). Init function `FUN_08011bc8(uart)`, called for USART2 (0x40004400, feed "jinsi") and UART7 (0x40015400, selector "qiehuan") with identical values. Writes, in order:

| Reg | Value | Decode |
|---|---|---|
| GCONF 0x00 | 0x000001dc | bit2 en_spreadcycle=1, bit3 shaft=1, bit4 index_otpw=1, bit6 pdn_disable=1, bit7 mstep_reg_select=1, bit8 multistep_filt=1; I_scale_analog=0, internal_Rsense=0, index_step=0, en_pwm_mode(spread)=on |
| IHOLD_IRUN 0x10 | 0x000a0900 (literal 0x08011c54) | IHOLD=0, IRUN=9, IHOLDDELAY=10 |
| TPOWERDOWN 0x11 | 0x80 | 128 |
| CHOPCONF 0x6c | 0x150082c3 (0x08011c58) | TOFF=3, HSTRT=4, HEND=5 (raw), TBL=1, vsense=0, MRES=5 (8 usteps), intpol=1, dedge/diss2g/diss2vs=0 |
| PWMCONF 0x70 | 0xc80d174b (0x08011c5c) | pwm_ofs=75, pwm_grad=23, pwm_freq=1, autoscale=1, autograd=1, freewheel=0, pwm_reg=8, pwm_lim=12 (unused: spreadCycle) |

NOT written by stock (chip power-on defaults): TPWMTHRS, TCOOLTHRS, SGTHRS, COOLCONF, any other register. No FACTORY_CONF/OTP writes found.

When written: once at boot (`FUN_080111a0` -> FUN_08011bc8 x2); on debug F43 (re-init both); and in `FUN_08017ad4` when flag 0x20000260 is set. That flag is set by the UART reply parser (`FUN_080126d0` @0x080126d0 for USART2, the twin parser at 0x080128a8 for UART7) when a GCONF read reply has low byte != 0xdc (driver reset / lost config): it runs the F112 stop (both EN high) then re-inits both drivers. F13 reads GCONF of both drivers each poll, so this is the only driver "health" check. NOT re-written per move or per channel. F42 S<1|2> I<n> writes IHOLD_IRUN live = (n<<8)|0xa0000 (n clamped 31; IHOLD stays 0); debug only.

## 2. Enable (EN) behaviour (stock)

GPIO helpers: `FUN_08011984` = reg +0x10 (set pin high), `FUN_08011980` = reg +0x14 (pin low). EN active low.

Selector (PB1), state machine `FUN_0801900c`:
- PB1 low (enabled) on every tick of a move state (homing states 1-3, move states 7/0xc/0x12/0x17/0x1d/0x22/..., manual 0x81).
- PB1 high (off) on arrival of every move (states 4, 7, 0xc, 0x12, ... "== target" branch) and at init and in error state 0x7e. So selector is energized only while stepping; parked = off.
- F24 (select chan): state 1 -> home (PB1 low) -> state 4 (PB1 high) -> move to slot -> PB1 high on arrival. F23: only clears a bit in a mask (no motion). F39 (release): state 0xc, moves to neutral 2048 then PB1 high.

Feed (PA5), via enable mask bytes 0x20000436 (requested) / 0x20000437 (applied), `FUN_0801874c` / `FUN_080186a0`:
- Bit set -> PA5 low (enabled). Set when a planned block has steps on the axis (`FUN_08016540` -> `FUN_08018678`).
- F10 (feed, states 10/0x15/0x20/0x2b -> 0xb/0x16/0x21/..) runs the move, waits for the queue to empty (`FUN_08016374`==0), goes to state 5 (ready). It does NOT release EN. PA5 stays low until F112 or an F11 finishing. Whether firmwareExe sends F112 after every F10 is host side, not in this binary (the host does after the toolhead sensor trips).
- F11 (unload, states 0xe/0x19/0x24/0x2f): ends in state 0x10/0x1b/.. = `FUN_08015d28` = planner stop + PA5 high + PB1 high. So F11 always releases the feed at the end.
- F112 (`FUN_08015d28`): PA5 high and PB1 high, state 5. Also called on GCONF mismatch.
- No idle timeout, no timer-based disable found anywhere. Stall/over-temp never stops the motors (F14/F40 only report).
- Standstill current: IHOLD=0 with IHOLDDELAY=10 and TPOWERDOWN=128 (~2.8 s at standstill, then ramp down). Per TMC2209 scale (CS+1)/32 that is 1/32 of full scale = about 0.014 A rms if the 0.5 ohm resistors are the sense resistors. Freewheel field = 0. How the MS35776 clone treats IHOLD=0: NOT verified (the idle feed does brake a strand, so it is not zero current).
- Motors are therefore left energized at standstill in stock only on the feed after F10 until F112, at IHOLD 0.

## 3. Feed motion profile (stock)

- Planner is Marlin-like trapezoid (`FUN_08016540`, `FUN_080158d0`, `FUN_08015768`). Timer TIM5 (0x40000c00): 144 MHz/36 = 4 MHz, period 2000 = 2 kHz tick. Step accumulator uses 2,000,000/rate (`FUN_080158b4`).
- Feed = axis 0. steps/mm = 343696245/1e6 = 343.696 (8 usteps). Max speed table 0x20000340 = {30000,30000,600,3200,3200} mm/min -> axis 0 = 500 mm/s (effectively no limit; host S is the speed). Accel table 0x20000440 = {700,350,600,100000,100000}; axis 0 = 700 (mm/s^2 by the x steps/mm scaling, inferred). Entry/exit step-rate floor 0x78 = 120 steps/s (0.35 mm/s).
- Host speeds seen: feed S1200 mm/min = 20 mm/s, unload S600 (10 mm/s), SILK/special 200-300 (3-5 mm/s).
- Selector: TIM6 144 MHz/72/156 = 12820 Hz, STEP toggled each tick = 6410 usteps/s = 140.86 deg/s constant, no ramp.
- Unresolved: the block step counts for axis 0 are mixed CoreXY style (A=x+y, B=x-y, both pins identical PA0), so whether stock emits 1 or 2 pulses per step on PA0 is not proven; the 640 mm lane measurement agrees with 343.7 steps/mm in Kalico, so treat as 1.

## 4. Thermal / current protection (stock)

- None active. DRV_STATUS (reg 0x6f) is read only by debug F44 (and F40-F64 dumps), never evaluated. No OTPW/OT check, no duty limit, no timeout.
- F14/F40 stall = Silk speed-sensor movement detection (ADC), reported only; no stop.
- Only auto-reaction: GCONF != 0xdc low byte -> stop + re-init.
- Real protection in stock is duty: short moves, EN released at end of F11/F112, IRUN 9 only.

## 5. Stock vs ours

Ours = AFC_Hardware-IFS.cfg + kalico-ad5x tmc2209 defaults. Nominal current = (CS+1)/32 x Vfs / (sqrt2 x (Rsense+0.02)); Vfs 0.32 (vsense0) / 0.18 (vsense1) as Kalico computes, Rsense 0.5 (unverified).

| Item | Stock | Ours | Verdict / heat impact |
|---|---|---|---|
| GCONF | 0x1dc | 0x1c4 (shaft=0, index_otpw=0, rest same) | DIFFERENT, harmless (dir pin inverted to compensate; index pin unused) |
| en_spreadcycle | 1 | 1 (no stealthchop_threshold) | MATCH |
| I_scale_analog / pdn_disable | 0 / 1 | 0 / 1 | MATCH |
| IRUN steady state | 9, vsense 0 = 0.138 A | 9, vsense 0 after `ifs_stock_current` (2 s after start) | MATCH only after the delayed_gcode runs |
| IRUN at startup | 9 | 31 with vsense 1 (0.245 A nominal): run_current 0.25 clamps to CS31/vsense1 in Kalico's helper (the cfg comment "keeps Kalico in vsense=0" is stale) | DIFFERENT during the first ~2 s, and permanently if the delayed_gcode fails or is not re-run; 0.245 A is 1.8x current = 3.2x motor heat vs stock |
| IHOLD | 0 | hold_current 0.01 -> ihold 0 (vsense1 and 0) | MATCH |
| IHOLDDELAY | 10 | 10 | MATCH |
| TPOWERDOWN | 128 | 128 | MATCH |
| CHOPCONF TOFF/HSTRT/HEND/TBL | 3/4/5/1 | 3/4/5/1 | MATCH |
| CHOPCONF vsense | 0 | 1 at start, 0 after delayed_gcode | as IRUN |
| MRES / intpol | 8 usteps / 1 | microsteps 8 / interpolate True | MATCH |
| PWMCONF | ofs75 grad23 freq1 as ag1 fw0 reg8 lim12 | ofs36 grad14, rest same | DIFFERENT, no effect (spreadCycle) |
| TPWMTHRS | not written (0) | 0xFFFFF | DIFFERENT, no effect while en_spreadcycle=1 |
| TCOOLTHRS/SGTHRS/COOLCONF | not written (0) | SGTHRS 0, COOLCONF 0 | MATCH |
| Re-write per move | never | not re-written unless AFC sets print_current (not set) | MATCH |
| Feed EN lifetime | on during F10 move; stays on until F112/F11 end; host sends F112 | AFC `do_enable`; in earlier config AFC `sync_to_extruder` kept the drive enabled and stepping for the whole print (patched 2026-10-25 to disable instead) | UNKNOWN for current AFC lane.move end (AFC source not local). Biggest heat suspect: continuous IRUN for hours when synced |
| Selector EN | only while stepping | AFC `select_lane(disable_selector)` / return_to_home disable | UNKNOWN per call path; 5 s left-on test showed no problem |
| Idle disable | none in stock; EN released by F11/F112 | no idle disable in our cfg | UNKNOWN (Kalico idle_timeout behaviour on AFC steppers not checked) |
| Feed speed | S1200 = 20 mm/s, S600 = 10 mm/s | 20 mm/s long/short | MATCH |
| Feed accel | 700 (inferred) | 100 | DIFFERENT, slower ramp, no heat concern |
| Steps/mm | 343.696 | 1600/4.655 = 343.72 | MATCH |
| Selector speed / ramp | 140.86 deg/s, none | 140 deg/s, accel 4000 | MATCH (close) |

## Likely overheat causes, in order

1. Drive left enabled and stepping (sync_to_extruder) during a print at IRUN while the clamped filament holds the lane: stock never energizes the feed while printing.
2. Before `ifs_stock_current` existed (or whenever it did not run), the feed ran at vsense1/CS31 = 0.245 A nominal, 1.8x stock current.
3. Feed commanded against a jam or after F10 with no F112 equivalent, so IRUN/IHOLD-delay current at a blocked motor.

Not verified: that the R500 parts are the sense resistors (current figures scale with them), 35BYJ46 winding resistance, clone IHOLD=0 behaviour.
