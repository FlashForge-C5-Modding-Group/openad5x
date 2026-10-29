# IFS

The IFS is the AD5X's four-lane filament feeder: one selector motor that clamps a lane onto a feed wheel, one feed motor, four filament sensors and four speed sensors. It has its own MCU, a Nations N32G455 board, which talks to the printer over RS485 on `/dev/ttyS4`.

OpenAD5X runs the IFS with Kalico firmware as a unit of AFC, and matches the stock behaviour decoded from the stock firmware.

| Page | What is in it |
|---|---|
| [Hardware](hardware.md) | The board, the chip, the pin map, the sensors and what is still unknown |
| [Stock IFS firmware](stock-firmware.md) | What the stock firmware does: memory layout, host protocol, selector, drivers, load and unload |
| [Kalico firmware](kalico-firmware.md) | The Kalico build for the IFS, flashing, the bootloader request and the RS485 half-duplex link |
| [IFS in AFC](afc-integration.md) | How the unit is installed and configured, and why |

## Decoded stock behaviour

These pages hold the detail from the stock `firmwareExe` and IFS firmware.

| Page | What is in it |
|---|---|
| [Host flows](STOCK_SPEC_HOST.md) | Every host-side flow, in call order: load, change, unload, pause, runout, end of print |
| [IFS firmware](STOCK_SPEC_IFS.md) | The IFS side of those flows |
| [Load wizard](STOCK_LOAD_WIZARD.md) | The load wizard step by step |
| [Feed acceleration](STOCK_FEED_ACCEL.md) | The feed planner |
| [Motor drive](STOCK_MOTOR_DRIVE.md) | How the motors are driven |
| [Sensor timing](STOCK_ADC_TIMING.md) | ADC sampling and the speed sensors |
| [Stall and LEDs](STOCK_STALL_LED.md) | Stall detection and the LED pins |
| [Release behaviour](STOCK_HOST_RELEASE.md) | When the host releases the lanes |
| [Motor specification](IFS_MOTOR_SPEC.md) | Motor parameters |

The configuration, options and commands that run the IFS on the printer are in `config-docs/IFS.md` in `AD5X-FS`.
