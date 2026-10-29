# IFS hardware

## Board

`FFP0302_Main_Board_V1.0.4` (2024-08-05), FlashForge part 20004780001.

- U5: Nations N32G455, with an X1 12.000 MHz crystal
- U3 and U4: stepper drivers. The marking reads MS35776, a TMC2209-compatible UART clone
- U1: GM3085E RS485 transceiver
- J1 "485-IN": 4-pin Microfit with 24 V, GND, A, B
- J2 to J5, Silk1 to Silk4: GND, VCC, Speed, Silk (per slot: filament present, and movement)
- Zero_CHK: SIG, VCC, GND. The selector home sensor, on PB9
- J8 "A" and J7 "B": motor connectors, with R500 sense resistors
- J9: VCC, CLK, DIO, GND. This is SWD, the recovery path with an ST-Link
- J6: 3-pin, on the back, unlabelled
- D4 (OK) and D5 (ERR) LEDs

## Chip: Nations N32G455

- The ADC init uses `0x40020C00`, `0x40021800` and `0x40021C00`, which are exactly the N32G45x ADC2, ADC3 and ADC4. ADC3 and ADC4 exist on the G455 only.
- The UART at `0x40015400` (PC4 and PC5, 9600) is a timer on the STM32F1 and GD32F30x, and UART7 on the N32G45x.
- Clock: `CFGR |= 0x30000 | 0x081C0000` is HSE/2 x24 (PLLMUL bit 4 at bit 27). The 12 MHz crystal gives 144 MHz, the N32G45x maximum (the GD32F303 maximum is 120).
- The ADC on PB12 to PB15 is on ADC3 and ADC4, which means the N32G455.
- The hardware FPU is used (`vldr` and `vmov d0`): Cortex-M4F.
- Kalico supports it as `MACH_N32G455`. It reports itself as `stm32f103xe`, uses `STM32_FLASH_START_10000` (a 64 KiB bootloader offset), and the default `RAM_SIZE` for the N32G45x is `0x10000`.
- The AD5X mainboards also report `stm32f103xe` at 144 MHz, so they are probably N32G45x too.

## Pins

| Pin | Mode | Use |
|---|---|---|
| PA9 / PA10 | AF_PP / IPU | USART1 TX/RX, 115200: host link (`ttyS4`) |
| PA11 | Out_PP, low at init | RS485 direction for USART1: high = transmit, low = receive |
| PA2 / PA3 | AF_PP / IPU | USART2 TX/RX, 9600, DMA1: the feed motor's TMC ("jinsi") |
| PC4 / PC5 | AF_PP / IPU | UART7 TX/RX, 9600, DMA2: the selector motor's TMC ("qiehuan") |
| PA0 | Out_PP | feed motor STEP |
| PA1 | Out_PP | feed motor DIR, with a per-motor invert flag |
| PA5 | Out_PP | feed motor EN, active low: high at init and in the F112 stop, low to enable |
| PA7 | Out_PP | selector motor STEP, toggled per timer tick |
| PA6 | Out_PP | selector motor DIR: high = positive (count up) and home seek, low = back off |
| PB1 | Out_PP | selector motor EN, active low: low while moving, high at init, on arrival and in the F112 stop |
| PB9 | IPU | selector home sensor, 0 = triggered |
| PB5 (high), PB6 (low) | Out_PP | LEDs (probably D4 and D5), only set at init |
| PC0 / PC2 / PB12 / PB14 | analog | Silk1 to Silk4 filament sensors (ADC2 ch6, ADC2 ch8, ADC4 ch3, ADC4 ch4) |
| PC1 / PC3 / PB13 / PB15 | analog | Speed1 to Speed4 movement sensors (ADC2 ch7, ADC2 ch9, ADC3 ch5, ADC4 ch5) |

Peripherals the stock firmware uses: GPIOA, GPIOB, GPIOC, AFIO, EXTI, USART1 to USART3, TIM1 to TIM8 and `0x40015000`/`0x40015400`, DMA1, RCC, FLASH and PWR.

### Sensors

- Each input is averaged over 20 samples.
- **Silk (filament present):** the flag is set when the average is below 900 or above 3100, and cleared when it is between 1001 and 2999. A rising edge sets a bit in `ffs_channels_insert`.
- **Speed (movement):** the window is 1400 to 2636 or 1200 to 2800, and the values are logged to ring buffers that feed `stall_state`.
- The slot order (bit 0 to 3 = slot 1 to 4) is assumed to match the Silk1 to Silk4 connector numbering.

## Open questions

- What PB5 and PB6 do (probably the OK and ERR LEDs D4 and D5)
- Which motor connector (J8 "A" or J7 "B") is the feed motor and which is the selector
- The driver chip marking (MS35776?) and how closely it matches the TMC2209 in Kalico
- Whether the R500 resistors are the sense resistors
