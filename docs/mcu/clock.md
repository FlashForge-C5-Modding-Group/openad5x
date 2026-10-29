# Clock

All three boards (mainboard, eboard and IFS) use the same clock set-up.

## Stock

The Nations SDK `SystemInit` is the same in all three firmwares:

- HSE on, `CFGR &= 0xf7c0ffff; CFGR |= 0x081f0000`: PLL source HSE, HSE/2, `PLLMULFCT` `0x17` = x24. The 12 MHz crystal gives **144 MHz**.
- `CFGR |= 0x2000 | 0x500`: APB2 /2 (72 MHz) and APB1 /4 (36 MHz).
- Flash latency 4.
- Without HSE, `SystemCoreClock` is 8000000 (HSI).

## The problem in Kalico

`kalico-ad5x`'s N32G45x support uses the generic STM32F1 `clock_setup()` (`src/stm32/stm32f1.c`), and `CLOCK_FREQ` is fixed at 128 MHz for the N32G45x (no prompt in `Kconfig`):

- With `STM32_CLOCK_REF_12M` the divider is 128/6 = 21, which is above 16, so it is halved to 10. HSE x10 is 120 MHz, while Kalico assumes 128 MHz, which is a timing error of about 6.7%.
- It also sets flash latency 2 and APB1 /2, where stock uses 4 and /4.

## The fix

Mainline Klipper has its own N32G45x clock code in `src/stm32/stm32f1.c` (the N32 power register `PWR_BASE + 0x0c`, flash latency from the clock, APB /4 above a limit) and a default of 144000000 for the N32G45x in `Kconfig`. With a 12 MHz crystal it uses a divider of 24 and HSE x12, which is 144 MHz.

`kalico-ad5x` carries that clock code and the 144 MHz default for all three boards. The IFS build also drops to HSI and stops the PLL before reconfiguring, like the stock `SystemInit`.

Checked on the mainboard: Moonraker reports `CLOCK_FREQ` 144000000 and a measured frequency of 144000685. Without the patch it would have been about 120 MHz.
