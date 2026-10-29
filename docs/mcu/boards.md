# Boards, pins and power

## Stock packages used

The facts on these pages come from the stock firmware packages:

- The control package (`main-update/control-extracted/`): `AD5X.bin`, `ADM_App.hex`, `run.sh` and the flash tools
- The software package 3.1.6: `printer.base.cfg`, FlashForge's klippy files and `firmwareExe`
- The factory image's `printer.cfg`, for the extruder section. The copy in the factory image's `usr/data/config/` is ZMod-modified and not used.

## Mainboard

`FFP0302_Main_Board_V3.0.0`, 2024-9-22.

- The MCU is the square QFP to the right of the SoC. The SoC sits under a shield frame left of centre.
- A JTAG header at the top edge next to the USB-C connector (likely SWD to the N32), a `GND TX RX` header (J33) bottom middle, and 3 stepper drivers with heatsinks.

## MCUs

| | Mainboard `mcu` | Toolhead `eboard` |
|---|---|---|
| Host port | `/dev/ttyS2`, 230400 | `/dev/ttyS5`, 230400 |
| Stock firmware | `AD5X.bin` | `ADM_App.hex` |
| Stock build | `?-20241125_172251-ubuntu` | `?-20241122_134741-ubuntu` |
| MCU (reported) | `stm32f103xe`, 144 MHz | `stm32f103xe`, 144 MHz |
| Serial pins | PA10/PA9 (USART1) | PA10/PA9 (USART1) |
| App address | `0x08000000` (no FlashForge bootloader) | `0x08010000` (64 KB bootloader) |
| Flash tool | `NationsCommand -c -d --fn AD5X.bin --v -r` | `IAPCommand ADM_App.hex /dev/ttyS5` |
| Initial SP | `0x20020000` | `0x20020000` |

- Both are Nations N32G45x. They use the N32 ADC1 (`0x40020800`) and never the STM32 ADC1 (`0x40012400`), and a stack at `0x20020000` needs 128 KB of RAM (the STM32F103xE and GD32F303xE have 64 KB).
- Kalico's N32G45x build also reports `stm32f103xe`.
- The build info is in the zlib data dictionary inside each firmware.

## Pins (stock config)

### Mainboard

| Function | Pins |
|---|---|
| `stepper_x` | step PB13, dir PB12, enable !PB1, TMC2209 UART PB11, endstop `!eboard:PA15` |
| `stepper_y` | step PC4, dir PA7, enable !PA2, TMC2209 UART PB0, endstop !PC12 |
| `stepper_z` | step PC7, dir PC8, enable !PB14, TMC2209 UART PB15, endstop PD2 |
| `heater_bed` | heater PB9, sensor PA0 (Generic 3950, 4700 pullup), max_power 0.4 |
| probe | !PB3 (the load cell trigger; the load cell itself is on host `ttyS7`) |
| Chamber LED | PA11 |
| `pcb_fan` | PA5 |

- X, Y and Z TMC2209: `sense_resistor` 0.10. X and Y run 1.1 and hold 0.9, Z runs 0.9 and holds 0.9.
- CoreXY, `rotation_distance` 40 for X and Y and 8 for Z, microsteps 16.

### Eboard

| Function | Pins |
|---|---|
| Extruder | step PB14, dir !PB15, enable !PB12, TMC2209 UART PB10 (run and hold 0.8, sense 0.10) |
| Extruder heater | heater PA8, sensor PA0 (Generic 3950), max_temp 350 |
| `heat_fan` (hotend) | PB4 |
| `fanM106` (part cooling) | PB5 |
| `lis2dw` accelerometer | CS PA4, software SPI sclk PA5, mosi PA7, miso PA6 |
| `filamentValue` sensor | PA3 (read as a Generic 3950 temperature sensor) |
| `cutValue` sensor | PA2 (read as a Generic 3950 temperature sensor) |
| X endstop | PA15 |

- The extruder uses microsteps 16, `gear_ratio` 50:10, `rotation_distance` 21.9 and `pressure_advance` 0.04.

## Eboard power pins

Under Kalico the hotend heater did not heat: with `power 1.0` the temperature stayed at 24 °C, and `verify_heater` shut down with "Heater extruder not heating at expected rate".

- The stock eboard firmware sets PB1 and PB7 as push-pull outputs in its init, before the main loop, and drives both high. PB1 stays high. PB7 is cleared later in the main loop, once a flag is set. Neither pin is in the Klipper config, so under Kalico they float.
- Driving PB1 alone did not help. **PB7 is the hotend heater power enable**: with PB7 high the heater went from 24 to 62 °C in 15 s and held 60.
- `firmwareExe`'s host GPIOs (`gpio_out`) are only used by `doPowerOff`, `printCompletedPowerOff` and `sLightCheck`, not for the heaters.
- The stock mainboard firmware only has PC0 (the load cell `level_res`) as a fixed output.
- The bed heater works under Kalico unchanged: `M140 S50` took the bed from 25 to 34 °C in 30 s at `max_power` 0.4, with no extra power pin.

The config that fixes it:

```ini
[static_digital_output eboard_power]
pins: eboard:PB1        # stock keeps it high

[output_pin heater_power]
pin: eboard:PB7
value: 1
shutdown_value: 0       # shutdown cuts heater power
```

## `pcb_fan`

`[fan_generic pcb_fan]` on PA5 stays off until `SET_FAN_SPEED` is sent. Under Kalico nothing sent it, and the Y TMC2209 shut down on over-temperature (`ot=1 t120`) in the middle of a print.

- Stock `firmwareExe` sends `SET_FAN_SPEED FAN=pcb_fan SPEED=1` in `SerialObject::serialPrint` before `M24`, and `SPEED=0` in its end and cancel cleanup. It also sends 1 and then 0 in `FourToOne::changeStart` (an IFS change), `Filament::dryingStart` and auto calibration, and there is a manual toggle in More Info.
- There is no SoC temperature to drive it: the X2600 kernel has no thermal or hwmon driver, and stock never read one.
- The Kalico `printer.base.cfg` uses `[controller_fan pcb_fan]` with `pin: PA5` and `heater: extruder` (all steppers by default). The fan is on while any motor is enabled or the hotend heats, and off 30 s after idle. That covers prints, IFS changes and cancels, like stock.
