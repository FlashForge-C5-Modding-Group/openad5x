# STOCK IFS (v3.0.7) feed motor accel/decel, reverse engineered (read-only)

Sources: `ifs_v.c` (Ghidra), `ifs.bin` (base 0x08010000), `ram_init.bin` (RAM 0x20000000..0x20000490), Ghidra disassembly (headless, on a COPY of the project). Nothing was run against any printer. Marks: [V] verified in decompile/disassembly, [I] inferred from structure (Marlin-1.1-like planner), [U] uncertain.

## Answer in one paragraph

Feed = axis 0 (F10 `L` mm goes on axis 0 only), speed = `S/60` mm/s. The planner is a Marlin trapezoid. Acceleration = **500 mm/s^2 = 171848 steps/s^2** (the literal 500, and the per-axis cap for axes 0 and 1 is also 500). The 700 in table 0x20000440 is NOT used by the planner. A lone F10/F11 block enters and exits at the 120 steps/s floor (0.349 mm/s), so the move is a plain 0 -> S -> 0 trapezoid at 500 mm/s^2. At the end of a move there is no further ramp: it just stops after the last step at 120 steps/s. F112 / planner reset stops instantly (no ramp) and then disables the driver.

## 1. Axis and units (F10)

- F10 handler 0x08012ed8: `strchr` for 'L' (0x4c) and 'S' (0x53), `atof` (FUN_08014908), float store to 0x200000e4 (L) and 0x200000ec (S) [V disasm 0x08012ed8-0x08012f4c; pool 0x080131e8 = 0x200000e4, 0x080131ec = 0x200000ec]. ram_init: L = 0, S = 600.0.
- F10 start state 10 of the TIM6 state machine FUN_0801900c calls `FUN_080163bc(*0x200000e4, *0x200000ec)` [V ifs_v.c line 8067]; F11 uses 0x200000e0 (L, stored negated) / 0x200000e8 the same way (line 8108).
- `FUN_080163bc(s0 = dist_mm, s1 = speed_mm_min)`, disasm 0x080163bc-0x0801642c: zeroes position and a 5-float target array at 0x20000c98, then `vstr s16,[0x20000c98]` (dist goes to element 0 only), `vdiv.f32 s1,s17,s0` with s0 = 60.0 (pool 0x0801649c = 0x42700000), then `bl 0x08017b80` with r0 = 0x20000c98. So axis 0, speed = S/60 mm/s.
- `FUN_08017b80(speed_mm_s, target*)` [V]: steps = round(target[i] * steps_per_mm[i]); steps_per_mm = (float)(0x2000032c[i] = 0x147c6375 = 343696245) / 1e6 (double 1e6 at 0x08018538) = 343.696245, stored at 0x20005ca4 + i*0x30 + 4. Mode mask 0x20000460 = 0x1f (ram_init) -> all axes relative: new = prev + round(). N = round(dist * 343.696245). Per-axis mm delta `0x20001604[i] = delta * 0x20005da8[i]` (= 1/steps_per_mm). Block step counts: A = |d0+d1| (block+4), B = |d0-d1| (block+8), Z (+0xc), E0 (+0x10), E1 (+0x14); step_event_count (block+0x18, RAM 0x20000310) = max of them = N for a feed move. Length 0x2000030c = sqrt(d0^2+d1^2+d2^2) = N/343.696 mm.
- Speed cap: `0x20000340[i]` = 30000 (axis 0), divided by double 60.0 (0x08018544) = 500 mm/s into 0x20005ca4 + i*0x30 + 8. If speed*|d_i|/len exceeds it the speed is reduced (ifs_v.c lines 7208-7215). Feedrate multiplier 0x20000070 = 1.0 (ram_init 0x3f800000); `0x20000460 & 0x80` = 0 so no extra scaling [V].
- Call into the planner (disasm 0x080180ac-0x080180be): `FUN_08016540(s0 = 0x20000470 (mm/s), r0 = steps/s (overwritten later), r1 = *0x2000046c (= 0), r2 = 1, r3 = *0x2000046c)`.

## 2. Block acceleration (block+0x74) in FUN_08016540

Decompile lines 6281-6411:
1. Extrude-only branch: `if (block+4 == 0 && block+8 == 0 && block+0xc == 0)`: `accel = ceil(steps_per_mm_of_move * 500.0)` (float 500.0 at DAT_08016e54 = 0x43fa0000 [V]). Not taken for the feed (block+4 = N).
2. Otherwise: `accel = ceil((float)500 * (N / len))` with the integer literal 500 (`VectorSignedToFloat(500)`, line 6301) = ceil(500 * 343.696) = 171848 or 171849 depending on float rounding. [V] The RAM variable 0x200002ec (500) is not read here.
3. Advance branch (`block+0x3f`) needs an E delta (iVar12 != 0): never for the feed. `block+0x3d` = 0x2000046c = 0. `0x20000304` (ram_init 0; 0.04 for [0],[1] from FUN_080171c0 line 6586) is only the linear-advance K, unused.
4. Per-axis cap loop (lines 6348-6409): for axes 0..3 with block steps != 0 (A and B): `accel = min(accel, cap[i] * step_event_count / steps_i)`, `cap[i] = 0x200015a0[i]`. N/N = 1, so accel = cap = 171848.1 -> (uint) 171848.
5. `0x200015a0[i] = (float)0x200015c8[i] * steps_per_mm[i]` (FUN_080171c0 lines 6596-6601). `0x200015c8` = {500, 500, 50, 500, 500} written in FUN_08018dbc (lines 7863-7867; the 0x497ffff0/steps_per_mm = 3051 clamp is not hit). No other writer found. Init chain: boot -> FUN_080164a4 (line 5709) -> FUN_08018dbc -> FUN_080171c0.
6. **0x20000440 {700, 350, 600, 100000, 100000}** (ram_init) is only read in FUN_08018264 (line 7399) to fill `0x20005ca4 + i*0x30 + 0x10/+0x14` (= +-accel*steps/mm, halved for axes 0,1). I found no reader of those two fields in the decompile, so for the feed it is dead data [V no reader found; U for a reader through an unseen alias]. The earlier "700" in STOCK_MOTOR_DRIVE.md is wrong for the planner.
7. Stored: block+0x74 = accel (steps/s^2); block+0x5c = accel / (N/len) = 499.9996 mm/s^2; block+0x38 = (uint)(accel * 8.388608) = 1441565 (double 8.388608 = 2^24/2e6 in the pool at 0x08016e74) [V].

## 3. Effective acceleration, entry/exit

Effective acceleration: 500 mm/s^2 (499.9996), 171848 steps/s^2, for F10 and F11, both directions. Not 700.

Lone block (every F10/F11, because the state machine waits for an empty queue: states 0xb, 0xf, 0x16, ...):
- New block entry_speed^2 (block+0x50) = 0.0025 (DAT_08017110 [V disasm 0x08017088]) = 0.05 mm/s. Reverse pass `FUN_08017648` loops `while (prev(head) != planned_ptr)`; with one block both are equal so the body never runs [V]. Forward pass `FUN_0801735c(NULL, ...)` does nothing [V]. Junction jerk (0x2000158c = {10,10,0.3,20,20} mm/s, line 6591) only feeds block+0x54 (max_entry) and is not applied to a lone block.
- Tail of FUN_08017430 (disasm 0x080175a0-0x080175aa) calls `FUN_080158d0(entry = sqrt(entry^2)/nominal, exit = 0.05/nominal)`; 0.05 is the literal at 0x0801763c = 0x3d4ccccd [V].
- `FUN_080158d0` [V decompile 5290-5378]: `initial = ceil(nominal_rate * entry)`, `final = ceil(nominal_rate * exit)`, both clamped to >= 0x78 = 120 steps/s. So initial = final = 120 steps/s = 0.349 mm/s.
  `accelerate_steps = ceil((nominal^2 - initial^2) / (2 accel))` (FUN_08015bf0 = (p2^2 - p1^2) / (2 p3)), `decelerate_steps = floor((nominal^2 - final^2) / (2 accel))`, `plateau = N - acc - dec`; if negative: `acc = ceil((2 accel N - init^2 + final^2) / (4 accel))` clamped to [0, N], plateau 0. Stored: block+0x30 accelerate_until, +0x34 decelerate_after = acc + plateau, +0x6c initial_rate, +0x70 final_rate. That FUN_08014660 / FUN_080146e0 / FUN_08014548 are ceil / floor / ceil comes from their bodies [I].
- nominal_rate (block+0x64) = ceil(N * speed / len) = ceil(343.696 * speed) (lines 6243-6248).
- Queue slowdown (lines 6213-6224, 0x200002fc = 4) only acts when more than 1 block is already queued: not for a lone block.
- Consecutive F10 commands are separate stop/start blocks; no junction speed ever applies.

## 4. Tick routine and stops

- TIM5 update IRQ = `vec_66` 0x080124d8 -> FUN_08015ba4 -> `FUN_0801813c` (scheduler) -> `FUN_080177a8` (step) and `FUN_080152a4` (next interval). TIM5 registers touched: +0x2c ARR (FUN_080126cc), +0x24 CNT, +0x14 EGR, +0x0c DIER [V]. After an update event the counter restarts, so period = ARR + 1 ticks [I].
- Tick unit: FUN_08015768 sets TIM5 prescaler = 144e6 / 4e6 - 1 = 35; the planner interval is `2,000,000 / rate` (FUN_080158b4), i.e. the design clock is 2 MHz = 72 MHz timer clock (FUN_08012008 sets CFG |= 0x500, PPRE1 = /4, timers x2) / 36. **[U] I did not prove the timer clock is 72 MHz. If it were 144 MHz, TIM5 would run 4 MHz and every step interval would be half, i.e. all speeds 2x S.** Idle poll ARR = 1999 gives 1 kHz, not the "2 kHz" in older notes (which assume 4 MHz). By the same reasoning TIM6 (selector) would be 72 MHz / 72 / 156 = 6410 Hz toggle rate, not 12820 [U].
- One step per event: FUN_080158b4 sets 0x200002a8 = 1 on every call; FUN_080177a8 loops `0x200002a8` times over `FUN_080188bc(0)`; only axis 0 is ever stepped (disasm 0x08017906-0x08017908: `movs r0,#0; bl 0x080188bc`). Bresenham with steps == N gives exactly one pulse per event: STEP pin high then low (`FUN_08018798(0,1)`, `(0,0)`) on PA0 [V], DIR via FUN_0801856c. The pulse is skipped (and motion flags 0x20000428/2d cleared) if 0x2000019c != 0 with the dir flag set (ram_init 0x2000019c = 0) [I].
- Per event (FUN_080152a4, Marlin ISR) [V]: block load sets acc_time = dec_time = 0, `acc_step_rate = initial`, first interval = 2e6 / initial = 16666 ticks (8.33 ms) before step 1. After each step (`completed` already incremented):
  - `completed <= accelerate_until`: `rate = mulh(acc_time, accel_rate) + initial`, capped at nominal; interval = 2e6 / rate; `acc_time += interval`.
  - `completed > decelerate_after`: `r = mulh(dec_time, accel_rate)`; `rate = acc_step_rate - r` floored at final (final if r >= acc_step_rate); `dec_time += interval`.
  - otherwise cruise: interval = 2e6 / nominal.
  `mulh` = FUN_08011d34 = `(a*b + 0x800000) >> 24`. rate = t * accel in steps/s exactly (8.388608 * t_ticks / 2^24 = t_ticks / 2e6).
- End of block: last step, block dropped, next block loaded or idle interval 2000 ticks; EN is not touched. So the move ends with the decel ramp down to 120 steps/s then an instant stop from 0.349 mm/s. There is no extra stop code in the F10/F11 path.
- F112 (ifs.c line 3599 -> `FUN_08015d28`): `FUN_08017968` clears DIER bit 0 (TIM5 update IRQ off), moves head/planned/next pointers to tail (queue emptied), sets current block pointer 0x20000264 = 0, resyncs positions, re-enables the IRQ; then PA5 high (feed driver disabled) and PB1 high. A mid-move F112 is therefore an IMMEDIATE stop (no ramp, steps cease at whatever rate), and the driver is released. The F11 end state calls the same routine. F24/F39/F18/F30/F15 do not reset the planner.

## 5. Simulation results

`extra_tick=1` adds the +1 tick of ARR+1 per step [U].

| move | nominal | accel until | decel after | time to cruise | ramp distance | total (extra 0 / 1) | ideal Klipper a=500 |
|---|---|---|---|---|---|---|---|
| 50 mm S1200 (20 mm/s) | 6874 st/s | step 138 (0.401 mm) | step 17048 of 17185 | 47.7 ms (rate hits nominal at step 132, 0.384 mm) | 0.40 mm | 2.535 s / 2.544 s | 2.540 s |
| 50 mm S600 (10 mm/s) | 3437 st/s | step 35 (0.102 mm) | step 17151 of 17185 | 27.6 ms (step 29, 0.084 mm) | 0.10 mm | 5.017 s / 5.026 s | 5.020 s |

A Klipper trapezoid with max accel 500 mm/s^2, cruise S/60, start/end velocity about 0 reproduces stock within 0.2% (0.5% if the ARR+1 tick is real). The 8.3 ms first interval and up to 1 ms block pickup latency are not modelled.

```python
import struct, math

def f32(x): return struct.unpack('<f', struct.pack('<f', x))[0]
def rnd(x): return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))

TIMER_HZ   = 2_000_000                 # FUN_080158b4: 0x1e8480 / rate (TIM5 = 72 MHz timer clock / 36) [U clock]
SPM_D      = 343696245 / 1e6           # RAM 0x2000032c (0x147c6375) / 1e6 (double 1e6 at 0x08018538)
SPM        = f32(SPM_D)                # 0x20005ca4 + 4
INV_SPM    = f32(1.0 / SPM)            # 0x20005da8
ACCEL_MM   = 500                       # literal 500 in FUN_08016540 (also 0x200015c8[0] and [1])
CAP        = f32(float(ACCEL_MM) * SPM)  # 0x200015a0[0] = (float)0x200015c8[0] * steps/mm
MIN_RATE   = 0x78                      # FUN_080158d0
MIN_PLANNER_SPEED_SQR = f32(0.0025)    # DAT_08017110 / DAT_0801763c = 0.05 mm/s

def mulh(a, b):                        # FUN_08011d34 (MultiU24X24toH16 with rounding)
    return (a * b + 0x800000) >> 24

def calc_timer(rate):                  # FUN_080158b4
    return (TIMER_HZ // rate) & 0xffff

def plan(dist_mm, s_mm_min):
    v = f32(s_mm_min / 60.0)                              # FUN_080163bc /60.0 ; 0x20000070 = 1.0
    n = abs(rnd(f32(f32(dist_mm) * SPM)))                 # FUN_08017b80 round(target*steps/mm)
    d = f32(n * INV_SPM)                                  # 0x20001604[0]
    ln = f32(math.sqrt(d * d))                            # block+0x58
    inv = f32(1.0 / ln)
    f19 = f32(v * inv)
    nom_sqr = f32(f32(f32(ln * f19) * ln) * f19)          # block+0x4c
    nom_rate = int(math.ceil(f32(n * f19)))               # block+0x64
    spm_blk = f32(n * inv)                                # steps per mm of this block
    acc = int(math.ceil(f32(ACCEL_MM * spm_blk)))         # ceil(500 * steps/mm)
    if float(acc) > CAP:                                  # per-axis cap loop (axes A and B)
        acc = int(f32(f32(CAP * n) / n))
    acc_mm = f32(acc / spm_blk)                           # block+0x5c
    acc_rate = int(acc * 8.388608)                        # block+0x38
    nom = f32(math.sqrt(nom_sqr))
    ent_f = f32(f32(math.sqrt(MIN_PLANNER_SPEED_SQR)) * f32(1.0 / nom))   # lone block: entry = exit = 0.05 mm/s
    ini = max(MIN_RATE, int(math.ceil(f32(nom_rate * ent_f))))
    fin = ini
    def dist(a, b, ac): return 0.0 if ac == 0 else f32(f32(b * b - a * a) / f32(ac * 2.0))   # FUN_08015bf0
    acc_steps = int(math.ceil(dist(ini, nom_rate, acc)))
    dec_steps = int(math.floor(dist(nom_rate, fin, -acc)))
    plateau = n - acc_steps - dec_steps
    if plateau < 0:
        x = f32(f32(f32(f32(acc * 2.0 * n) - ini * ini) + fin * fin) / f32(acc * 4.0))
        x = math.ceil(x)
        acc_steps = n if max(x, 0) >= n else int(max(x, 0))
        plateau = 0
        dec_after = acc_steps
    else:
        dec_after = acc_steps + plateau
    return dict(n=n, nom_rate=nom_rate, acc=acc, acc_mm=acc_mm, acc_rate=acc_rate, ini=ini, fin=fin,
                acc_until=acc_steps, dec_after=dec_after)

def run(b, extra_tick=0):
    """FUN_080152a4 + FUN_0801813c. Returns step times in seconds and the rates used."""
    t = calc_timer(b['ini'])                 # first interval (block load)
    acc_time = dec_time = 0
    acc_rate_now = b['ini']
    done = 0
    clock = 0
    times = []
    rates = []
    while True:
        clock += t + extra_tick              # wait, then step
        done += 1
        times.append(clock / TIMER_HZ)
        if done >= b['n']:
            break
        if b['acc_until'] < done:
            if b['dec_after'] < done:        # decelerate
                r = mulh(dec_time, b['acc_rate'])
                if r < acc_rate_now:
                    r = acc_rate_now - r
                    if r < b['fin']: r = b['fin']
                else:
                    r = b['fin']
                t = calc_timer(r)
                dec_time += t
            else:                            # cruise
                r = b['nom_rate']; t = calc_timer(r)
        else:                                # accelerate
            r = mulh(acc_time, b['acc_rate']) + b['ini']
            if r > b['nom_rate']: r = b['nom_rate']
            acc_rate_now = r
            t = calc_timer(r)
            acc_time += t
        rates.append(r)
    return times, rates

if __name__ == '__main__':
    for s in (1200, 600):
        b = plan(50.0, s)
        for extra in (0, 1):
            times, rates = run(b, extra)
            tc = next(i for i, r in enumerate(rates) if r >= b['nom_rate'])
            print(f"S{s} 50mm extra_tick={extra}: {b}")
            print(f"  time to cruise {times[tc]*1000:.2f} ms at step {tc+1} = {(tc+1)/SPM_D:.3f} mm;"
                  f" decel starts step {b['dec_after']} ({b['dec_after']/SPM_D:.3f} mm);"
                  f" total {times[-1]*1000:.2f} ms; ideal trapezoid {50/(s/60)+(s/60)/500:.4f} s")
```
