# Kalico firmware on the IFS

The IFS runs Kalico (`kalico-ad5x`) in place of the stock firmware, as its own Klipper MCU: `[mcu ifs]` with `serial: /dev/ttyS4`, `baud: 115200` and `restart_method: command`. FlashForge's bootloader is kept, and Kalico is flashed at `0x08010000` with the stock `IFSCommand`.

## Build

The Kalico build config for the IFS is `mcu-firmware/ad5x/config/kalico-ifs.config` in `AD5X-FS`:

- `MACH_N32G455`, `CLOCK_FREQ 144000000`, `CLOCK_REF_FREQ 12000000`
- `FLASH_APPLICATION_ADDRESS 0x8010000`
- `STM32_SERIAL_USART1`, `SERIAL_BAUD 115200`
- `STM32_FLASHFORGE_IFS=y`, which selects the IFS-specific behaviour below

The data dictionary reports `stm32f103xe`, 144 MHz and 115200, with `RESERVE_PINS_serial PA10,PA9` and `RESERVE_PINS_rs485 PA11`. The Intel hex layout matches the stock `ifs.hex`.

### Stack pointer

Stock uses an initial SP of `0x20007498`. The eboard bootloader refuses an app with SP `0x20010000` and accepts `0x20020000`. For the IFS, `kalico-ad5x` sets `RAM_SIZE 0x8000` when `STM32_FLASHFORGE_IFS` is on, which gives SP `0x20008000`, and the IFS bootloader accepts it. The mainboard and eboard builds are unchanged.

### Clock

The stock clock is HSE/2 x24, which is 144 MHz from the 12 MHz crystal. `kalico-ad5x`'s original N32G45x support was fixed at 128 MHz and its generic STM32F1 `clock_setup()` gave only 120 MHz with that crystal, so `kalico-ad5x` carries a 144 MHz clock patch. See [Clock](../mcu/clock.md). The IFS build also drops to HSI and stops the PLL first, like the stock `SystemInit`.

## Bootloader request

The stock firmware reached its bootloader with the F37 command (see [Stock IFS firmware](stock-firmware.md#bootloader-entry-f37)). Kalico has a board patch that does the same: on a bootloader request it erases page `0x0800D000` and resets, so reflashing over `ttyS4` keeps working.

To request the bootloader from a running Kalico IFS, write `~ \x1c Request Serial Bootloader!! ~` at 115200 8N1 to `ttyS4` (Klipper must not be holding the port), then run the catch script straight away.

## Flashing

The stock `IFSCommand` protocol is XMODEM-like, 115200 8E1:

- The host sends `C` until the bootloader answers `0x06` (or `0x07`).
- Frames are `0x01`, a sequence byte, a 16-bit little-endian length, 1024 bytes of data (padded with `0xFF`) and a CRC16-CCITT (polynomial `0x1021`, initial value 0), which is 1030 bytes. Each frame is acknowledged with `0x06` or rejected with `0x15`. Then EOT `0x04` is answered with `0x06`.
- There are no addresses: the data is written from `0x08010000`.
- `IFSCommand` flushes after every write and waits 5 s per read. Its `stm32Reboot` and `stm32UpdateFLag` GPIO functions are never called.

The tools are in `AD5X-FS`, under `fs/usr/data/opencreator/mcu-flash/`:

| Tool | What it does |
|---|---|
| `ifs_capture.py <IFSCommand> <hex> <out.frames>` | Runs `IFSCommand` against a fake bootloader on a pty and saves its exact frames |
| `ifs_catch.py <port> <frames> <seconds>` | Sends `C` every 20 ms until the bootloader answers, then the frames and EOT. Works in the power-up window (unplug and replug the IFS cable) or after a bootloader request |
| `ifs_flash.sh` | Captures the frames, requests the bootloader, and catches it. Klipper must not hold `ttyS4` |
| `ifs_probe.py <port>` | Passive listen, a Kalico identify at 115200, 230400 and 57600, and a bootloader sync |

The bootloader only listens for a short window right after the IFS powers up (while the flag at `0x0800D000` is set).

The way back to the stock firmware is `IFSCommand /usr/prog/PROGRAM/control/1.1.1/ifs.hex /dev/ttyS4` while the bootloader is waiting. `ifsF37` no longer works once Kalico runs, because Kalico does not know F37.

## The host link

The host link is RS485: the AD5X has an RS485 converter on `ttyS4`, the IFS has a transceiver, and the cable is a 4-pin Microfit 3.0. PA11 is the direction pin, and stock drives it **high to transmit and low to receive**.

Kalico's `src/stm32` has no RS485 control, so the IFS build adds it in `serial.c`. Two problems had to be solved.

### Direction and turnaround

The host switches its RS485 driver in hardware (there is no kernel RS485 on `ttyS4`) and holds the bus briefly after its last byte, while Kalico answers within microseconds. Replies then arrive with the first one or two bytes corrupted. The IFS now waits a short turnaround after the last received byte before driving PA11 high, and the direction change and the TX interrupt are set up with interrupts off.

### Half duplex

Klipper pipelines frames, so the host transmits while the IFS answers and both are lost. With AFC, configuring the IFS hung forever, with 956 of 975 bytes retransmitted. The fix is to treat the IFS the way stock does, with the host as master:

- **IFS (`serial.c`):** output waits on a timer and only starts 1 to 2 ms (`RS485_GAP_US`, `RS485_WINDOW_US`) after the last received byte. A running burst continues, and the shutdown handler re-arms the timer.
- **Host (`klippy/chelper/serialqueue.c`):** a half-duplex mode, switched on by `serialhdl.py` when the MCU reports `SERIAL_HALF_DUPLEX=1`. One block is in flight, and nothing is sent or retransmitted until 2 ms (`HALF_DUPLEX_GAP`) after the last received byte and 4 ms (`HALF_DUPLEX_TX_HOLD`) after the host's own transmit ends. When idle, the host writes a lone `0x7e` (the MCU ignores leading sync bytes without a NAK), so the IFS gets a turn about every 4 to 5 ms.

After this, configuring the IFS takes 17 ms with no retransmits, the IFS `mcu_awake` fell from 12.7% to 1.7%, and homing no longer times out.

### Several Klippy instances

Several Klippy instances fighting over the ports leave the IFS in shutdown (`oids already allocated`). Busybox `ps` cuts the command line, so `klippy_restart.sh` matches `/proc/<pid>/cmdline`: it stops every `klippy.py` and starts one.

## Known problem

The IFS link still shows invalid and retransmitted bytes that keep climbing, even at idle. See [Status and roadmap](../status-and-roadmap.md).
