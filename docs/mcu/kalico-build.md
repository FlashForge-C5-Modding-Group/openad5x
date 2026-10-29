# Kalico build and kiln-os

## Build configs

The Kalico build configs are in `AD5X-FS`, under `mcu-firmware/ad5x/config/`:

| File | Board | Settings |
|---|---|---|
| `kalico-mainboard.config` | Mainboard | N32G455, no bootloader (`STM32_FLASH_START_0000`), 12 MHz crystal, USART1 on PA10/PA9, 230400 |
| `kalico-eboard.config` | Eboard | The same, with the 64 KiB bootloader (`STM32_FLASH_START_10000`) |
| `kalico-ifs.config` | IFS | N32G455, 64 KiB bootloader, 12 MHz, USART1, 115200, `STM32_FLASHFORGE_IFS` |

## Patches in `kalico-ad5x`

1. **Clock:** mainline Klipper's N32G45x clock code and the 144 MHz default, for all three boards. See [Clock](clock.md).
2. **RAM size:** `RAM_SIZE` of 128 KiB for the N32G455, because the eboard bootloader checks the stack pointer. The IFS uses `0x8000` (SP `0x20008000`) instead; stock IFS has an SP of `0x20007498`.
3. **Eboard reset:** `command_reset` sets `BKP->DR1 = 0x1234` and resets, and `bootloader_request` is a plain reset.
4. **IFS bootloader request:** erase page `0x0800D000` and reset, so the IFS can be reflashed over its serial port. See [Kalico firmware on the IFS](../ifs/kalico-firmware.md).
5. **IFS RS485:** direction control on PA11 and the half-duplex link. See the same page.

## FlashForge-only MCU commands

These exist in FlashForge's stock firmware and are not in Kalico:

- `Mainboard` and `Exboard`: board identification strings, used by the stock `checkEboard`
- `set_radar_interval` and `set_radar_sync_pulse`: purpose unknown ("radar")
- `i2c_modify_bits`, `i2c_set_software_bus` and `spi_set_software_bus`: older Klipper bus commands

## kiln-os

[kiln-os](https://github.com/djvalic/kiln-os) (GPL-3.0) is open firmware for the AD5X: mainline Klipper, Linux 6.6, a recovery OS and one-click updates. Its `klipper/` folder was a useful reference:

- Both boards are flashed with mainline Klipper `v0.13.0-803-g4cd711119`.
- `mcu-configs/ad5x-mainboard.config` uses `MACH_N32G455xE` (from the xblax/klipper Kconfig), `CLOCK_FREQ=144000000`, `STM32_CLOCK_REF_12M`, `STM32_FLASH_START_0000`, USART1, 230400 and `RAM_SIZE=0x20000`. `ad5x-eboard.config` is the same with `MACH_N32G455xC` and `STM32_FLASH_START_10000`. So both boards are N32G455 (mainboard xE, eboard xC).
- `mcu-patches/` against mainline Klipper:
    - **0001** (xblax): `command_reset` on the N32G455 with a 64 KiB bootloader writes `BKP->DR1 = 0x1234` and resets (bootloader bypass, which fixes `FIRMWARE_RESTART`).
    - **0002** (xblax): `bootloader_request` on the N32G455 with a 64 KiB bootloader is a plain `NVIC_SystemReset()` (the bootloader stays in IAP by default).
    - **0003:** `RAM_SIZE 0x20000` for the N32G455, because the eboard bootloader checks the stack pointer.
- It also has an IFS module (`klipper/extras/ifs.py`, `ifs.cfg`) that keeps the stock IFS firmware and translates to F-commands over `ttyS4`. OpenAD5X replaces the IFS firmware instead. A host-side patch, `patches/trsync-timeout-50ms.patch`, is included too.
