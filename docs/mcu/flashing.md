# Flashing and test builds

The three boards are flashed differently. The IFS has its own page: see [Kalico firmware on the IFS](../ifs/kalico-firmware.md).

## Mainboard

`NationsCommand` is the Nations N32 ISP over the chip's ROM bootloader on `/dev/ttyS2`. It toggles BOOT0 and RESET through host GPIOs (`/sys/class/gpio`); the GPIO numbers are not known yet. Recovery is always possible from the host, with no SWD needed.

```sh
cd /usr/prog/PROGRAM/control/1.1.1
./NationsCommand -c -d --fn /usr/data/kalico-fw/mainboard.bin --v -r
```

A flash shows the ISP at 9600 baud, BOOT Command Version V22, SubVersion V25 and the chip UID, then erase all, download, "Chip verification succeeded" and a reset. `NationsCommand` also deletes the 0-byte `UpdateM` file in its own folder.

Start FlashForge's own Klipper with `/usr/prog/klipper/start.sh`, never with `klipperDaemon start` directly: `start.sh` sets `LD_LIBRARY_PATH` for FlashForge's Python, and without it Klippy dies at once without writing a log.

**Way back to stock:** the same command with `/usr/prog/PROGRAM/control/1.1.1/AD5X.bin` (md5 `522b4641821016952cd4504e4c2177ed`).

## Eboard

The eboard has FlashForge's IAP bootloader at `0x08000000` to `0x0800FFFF`, and the app at `0x08010000`.

- **Plain reset:** the bootloader stays in IAP mode, waiting on `ttyS5` at 115200 and printing `Ready` lines. An `A` (`0x41`) is answered with ACK (`0x06`) and it starts the app. This is what `eboard_start()` in `startup.sh` does.
- **`BKP->DR1 = 0x1234` and a reset:** the bootloader skips IAP and starts the app at once. The stock code does it as: PWR and BKP clocks on, `PWR_CR.DBP` through bit-band `0x420E0020`, `BKP->DR1 = 0x1234` at `0x40006C00 + 4`, then `NVIC_SystemReset()`. This is used for Klipper's `reset` command.
- The bootloader does not start an app whose initial stack pointer is `0x20010000` (64 KiB RAM). Stock and kiln-os use `0x20020000`.

`IAPCommand` ("stm32isp") is `stm32isp [Options] <file> <comport> <baudrate>`, with `-verbose`. It reads Intel hex, uses `/sys/class/gpio` (probably the eboard reset), and deletes `/usr/prog/PROGRAM/control/Update` when it runs.

The eboard can only be flashed while its bootloader waits after power-on, before `eboard_start` sends `A`:

- `IAPCommand -verbose eboard.hex /dev/ttyS5` against a running app fails with "Can not connect to board, timed-out", and nothing is written.
- A Klipper `reset` sent to the stock app does not help either: the stock app resets with the `BKP DR1` bypass and goes straight back into the app.

So the flash is done by a boot hook in `startup.sh` (stock FlashForge also flashes the eboard at boot, in `run.sh`).

### The boot hook

In `eboard_start`, after `Ready`:

1. If `/usr/data/kalico-fw/eboard.flash` exists, read the hex path from it and delete the file.
2. Run `IAPCommand <hex> /dev/ttyS5`, logging to `/usr/data/logs/openad5x/eboard-flash.log`.
3. Reopen `ttyS5` and go round the loop again (`A` if the bootloader still waits, "application already running" if not).

A successful run logs `eboard: flashing ...`, `eboard: IAPCommand exit 0` and `eboard: application started`, and the flash log shows 36 frames, `STM32Write: success.` and `STM32iap finished NA.`.

**Way back to stock:**

```sh
echo /usr/prog/PROGRAM/control/1.1.1/ADM_App.hex > /usr/data/kalico-fw/eboard.flash
```

then reboot.

### What the printer shows after flashing

With only the MCUs on Kalico and FlashForge's Klipper still on the host, Klipper reports "MCU Protocol error" and lists both MCUs with the Kalico versions. The cause is `mcu 'eboard': Unable to extract params from: config_lis2dw`: FlashForge's `[lis2dw]` host module sends an older `config_lis2dw` than Kalico's firmware. This is expected and goes away once Kalico runs on the host.

With the mainboard on Kalico and the stock host, Klipper loads `137 commands` (stock: 116) and `1024 moves` (stock: 4096), and reaches `ready` with no protocol error.

## Test builds

Builds are made in WSL with `make` 4.4.1 and the Arm GNU Toolchain 14.2.rel1. The build script copies `kalico-ad5x` to a scratch folder and converts the copy to LF (the Windows checkout is CRLF, and `make` needs LF), copies in the board's `.config`, then runs `make olddefconfig` and `make`. The repository itself is never touched. A version string ending in `-dirty` comes from that LF conversion.

### Mainboard

Built from `kalico-mainboard.config`: `klipper.bin` 37104 B, version `v2026.10.00-160-ge5e1da62-dirty`.

| | Ours | kiln-os mainline | Stock `AD5X.bin` |
|---|---|---|---|
| Size | 37104 | 41432 | 37504 |
| SP | `0x20020000` | `0x20020000` | `0x20020000` |
| Reset vector | `0x08006871` | `0x08006cdd` | `0x08006ddd` |
| MCU / `CLOCK_FREQ` / baud | stm32f103xe / 144 MHz / 230400 | same | same |
| Serial pins | PA10, PA9 | same | same |

### Eboard

Built from `kalico-eboard.config`: `klipper.bin` 37512 B, and `klipper.hex` made with `arm-none-eabi-objcopy -O ihex klipper.elf`.

| | Ours | kiln-os `eboard.hex` | Stock `ADM_App.hex` |
|---|---|---|---|
| Load address | `0x08010000` | `0x08010000` | `0x08010000` |
| Size | 37512 | 41428 | 36012 |
| SP | `0x20020000` | `0x20020000` | `0x20020000` |
| `CLOCK_FREQ` / baud | 144 MHz / 230400 | same | same |
| Hex records | type 4 `0x0801`, 16-byte data, type 5, EOF, CRLF | same | same (some 8 and 12-byte records) |

The disassembly of `command_reset` shows the PWR and BKP clocks on (`RCC+0x1c |= 0x18000000`), `PWR_CR |= DBP`, `BKP(0x40006C00)+4 = 0x1234`, DBP off, then `NVIC_SystemReset`.
