# Stock IFS v3.0.7: lane sensor ADC sampling timing

Static analysis of the stock `ifs.bin` (base 0x08010000): the Ghidra decompile plus a disassembly listing. Nothing was run on a printer. [V] = verified in code, [I] = inferred from code plus datasheet/SDK knowledge, [U] = uncertain/assumed.

## 1. ADC clock tree and conversion

Init `FUN_08011a2c` (called from `FUN_080111a0`):
- `FUN_08011eac(0x18,1)` RCC+0x18 (APB2PCLKEN) |= 0x18 (GPIOB, GPIOC clocks). `FUN_08011e6c(0xe000,1)` RCC+0x14 (AHBPCLKEN) |= 0xE000 = ADC2/ADC3/ADC4 clocks (bits 13..15; the 0x40020C00/0x40021800/0x40021C00 ADC bases match ADC2/3/4) [I for bit names].
- `FUN_08010fa2(0,7)` -> `FUN_08011e48(0x100,0)`: RCC+0x2C (CFG2) `&= 0xFFFFFE0F` (ADCPLLPRES=0, ADCPLLEN bit8=0, PLL ADC clock OFF); `FUN_08011e30(7)`: CFG2 `[3:0] = 7` = ADCHPRES. [V]
- ADCHCLK divider table at flash 0x08019EB4 (read from ifs.bin): `01 02 04 06 08 0a 0c 10 20 ...`, index 7 = 0x10 = 16. Same table is used by the clock-reading routine `FUN_08011ecc` (`param_1[5] = HCLK / table[CFG2 & 0xf]`). So **ADC clock = HCLK / 16 = 144 MHz / 16 = 9.0 MHz** [V for /16, HCLK=144 MHz from your confirmed value].
- `FUN_08011e14(0x20000, 0x3800)`: CFG2 `&= 0xFFFF03FF | 0x20000 | 0x3800` = ADC1M source bit10=0 (HSI), ADC1MPRES bits[15:11]=7 (/8) -> 1 MHz reference (only for ADC power-up/cal). Bit 17 meaning [U]. Not part of the conversion rate.
- ADC CTRL3 (+0x58) is never written (only read for RDY, flag 0x20). CKMOD (bit 4) stays at its reset value; with the PLL ADC clock disabled the ADC runs from ADCHCLK [I; the Kalico driver also clears CKMOD for the HCLK mode]. RES (CTRL3[1:0]) stays at reset = 12 bit [I]; values are compared with 4095-scale thresholds (0x3e9, 2999, 0xc1c = 3100) so 12 bit is consistent.
- `FUN_08011144` (per ADC): CTRL1 mode independent, scan off; CTRL2: continuous off, align right, EXTSEL = 0xE0000 (=7, software trigger); RSEQ1 length 1. Then ADON, wait RDY, CAL (CTRL2 bit2), wait cal done. [V]
- Sample time: every read goes through `FUN_080110dc(adc, ch)` -> `FUN_08010fcc(adc, ch, 1, 7)`: SAMPT (+0x10 for ch<10, +0xC for ch>=10) = **7 for the channel = 239.5 cycles** (SDK enum `ADC_SAMP_TIME_239CYCLES5 = 7`), RSEQ3 slot1 = channel. [V code, SDK enum from kalico-ad5x `n32g45x_adc.h`]
- Conversion = 239.5 + 12.5 = 252 ADC cycles (12.5 per 12 bit conversion from the SDK/Kalico comment, [I]) = **28.0 us at 9 MHz**, plus under ~0.5 us for the register writes and flag clearing (about 70 core cycles) -> **about 28.5 us per read** [I].
- Trigger: **software, single shot, blocking.** `FUN_080110dc`: set sample time and sequence, `FUN_080110aa(adc,1)` = CTRL2 |= 0x500000 (EXTTRIG + SWSTART), poll STS (+0) bit1 (EOC) with no timeout, clear STS bits 1 and 4, return DAT (+0x4C) & 0xFFFF. No timer trigger, no DMA, no continuous mode, no ADC interrupt. [V]

## 2. How one sample is collected in FUN_08015ea0

- Main loop: `uVar5++; if (uVar5 > 1000) { uVar5 = 0; <read all 8 inputs> }  FUN_08017ad4();` (asm: `cmp.w r0,#0x3e8; bls 0x08015fca`, `0x08015fca: b 0x0801634a`, `0x0801634a: bl 0x08017ad4`, `0x0801634e: b 0x08015ec8`). [V]
- Inside one "round" the 8 inputs are read **back to back**, each a blocking `FUN_080110dc`, in this order: silk0 (ADC2 ch6), silk1 (ADC2 ch8), silk2 (ADC4 ch3), silk3 (ADC4 ch4), speed0 (ADC2 ch7), speed1 (ADC2 ch9), speed2 (ADC3 ch5), speed3 (ADC4 ch5). Only a few compares/stores between reads. One round = 8 x ~28.5 us = **~228 us** (cannot overlap: each waits for EOC). [V order, I timing]
- Each input has a counter 1..21: reads 1..20 add to the sum, read 21 stores `avg = sum / 0x14` (20) and resets sum and counter; read 21 itself is not added. So one stored average = **21 rounds**, with the 20 summed rounds spread over 20 x T_round. Samples are NOT taken back to back; consecutive samples of one channel are one full main-loop period (1001 passes) apart. [V]

## 3. Main loop pass time and real time between averaged values

Idle pass (no UART line pending, no flags), from the disassembly [V]:
`FUN_08017ad4` -> `FUN_08015c54` -> loop test `FUN_08017b60` (-> `FUN_08015c24` -> `FUN_0801496c`: ring-buffer count = `(size + head - tail) % size`, one `sdiv` + `mls`) returns 0 -> return; then two byte flag tests (0x200000b9, 0x20000260). About 60 Thumb-2 instructions, about 11 call/return/branch refills, 1 sdiv, about 8 literal-pool loads from flash. No delay loop, no SysTick wait, no UART wait in this path. [V]
- Count: roughly 100 core cycles if flash had no wait states = **0.7 us** at 144 MHz [I].
- Flash latency: `FUN_08012008` sets FLASH+0 (`AC`) `&= ~3; |= 4` -> 4 wait states at 144 MHz [V]. Whether prefetch/cache is on is not set here (reset default, [U]). Effective pass time is therefore **0.7 us (ideal) to about 3.5 us (no prefetch, every fetch stalls)**; best single estimate **about 1.5 us** [U, biggest uncertainty].
- Interrupts steal time: TIM6 ISR every 156 us (`vec_70` -> `FUN_0801900c`, idle case is a short switch), TIM5 ISR (`vec_66` -> `FUN_0801813c`, idle ARR 1999 at 2 MHz = 1 ms, i.e. about 1 kHz, but it is a planner loop of up to 10 iterations), SysTick every 20 ms (4 short blocks), USART1 DMA/IDLE. Estimated 2-5 % of the CPU when idle [U]; much more while stepping (TIM5 step rate) [U].
- Blocking work in the main context: command handling `FUN_08012de8` runs whole F-commands inline, some with TMC UART reads at 9600 baud (previous notes: F13 costs about 8 ms; the host sends F13 about once per second while printing). That pauses the ADC rounds about 8 ms per second (about 0.8 %). [V code exists, 8 ms from STOCK_STALL_LED.md B1]
- Round period: T_round = 1001 x t_pass / (1 - ISR load) + 8 x 28.5 us.

| case | t_pass | T_round | one averaged value (21 rounds) |
|---|---|---|---|
| min | 0.7 us | 0.9 ms | 18 ms |
| best estimate | 1.5 us | 1.8 ms | 38 ms |
| max | 3.5 us | 3.8 ms | 80 ms |

Measured from code: ADC clock, sample time, blocking structure, 228 us per round, 1001 passes, 21 rounds. Assumed: pass time (flash prefetch state, ISR load). The spread is about 4x and cannot be narrowed without a measurement (for example two F21 polls timed against value changes, which I did not do).

## 4. Consequence for the 50-entry odometer ring (SysTick 20 ms, FUN_080121bc)

- `FUN_080121bc` copies `avg[i]` (0x20000144 + 2i) into the ring `buf[k]` every 20 ms. It does **not** trigger or wait for a new ADC value. `avg[i]` only changes when the 21st round completes. [V]
- So with T_avg = 18-80 ms (best 38 ms): if T_avg > 20 ms, a SysTick tick sees the previous value again (fraction of fresh ticks about 20 ms / T_avg, e.g. about 50 % at 38 ms); only if T_avg < 20 ms (the optimistic end) would every tick see a fresh value (and some updates would be skipped). The ring therefore holds **runs of repeated values** in the likely case; the window still spans 50 ticks = 1.00 s, the threshold test (`|buf[k] - buf[0]| >= 15`) just sees changes up to one T_avg late. [V mechanism, U fraction]
- Each stored value is itself the mean of 20 samples taken over about 20 x T_round (about 18-76 ms), a built-in low-pass.

## Summary table

| quantity | value | evidence | certainty |
|---|---|---|---|
| ADC clock | 9 MHz (HCLK/16, PLL ADC clock off) | CFG2 low nibble = 7, table 0x08019EB4[7] = 0x10 | high (HCLK=144 MHz taken from your notes) |
| Resolution | 12 bit | CTRL3 never written, 4095 scale | medium |
| Sample time | code 7 = 239.5 cycles, all channels | `FUN_08010fcc(adc,ch,1,7)` | high |
| Conversion time | 252 cycles = 28.0 us (+~0.5 us overhead) | SDK 12.5 + 239.5 | medium |
| Trigger | software SWSTART, single, blocking poll on EOC, no DMA/IRQ | `FUN_080110dc`, EXTSEL=7 | high |
| One round (8 inputs) | about 228 us, back to back | code order | high (given conversion time) |
| Pass of main loop (idle) | 0.7 - 3.5 us, best 1.5 us | asm count, flash 4 WS | low |
| Time between samples of one channel | 0.9 - 3.8 ms, best 1.8 ms | 1001 x t_pass + round | low |
| Time between averaged values | 18 - 80 ms, best about 38 ms (21 rounds, 21st discarded) | as above | low |
| SysTick ring input | reuses last avg; repeats likely | `FUN_080121bc` reads 0x20000144 | high (mechanism) |
