# Differences from OpenCreator

OpenAD5X follows [OpenCreator](https://github.com/FlashForge-C5-Modding-Group/OpenCreator) (Creator 5) where the printers allow, so the two can share work. This is how the startup differs. It was last compared on 2026-10-10 and OpenCreator has changed since, so check its `opencreator-fs` repository before relying on a row.

| Part | OpenAD5X | OpenCreator |
|---|---|---|
| Startup | `startup.sh` core, then `startup.d/` drop-ins, run in order once per boot | `firmwareExe` script (Wi-Fi and watchdog), then a `startup.sh` loop, then `scripts/` run in parallel |
| NaN setting | NaN2008 builds, so no NaN byte is needed. `05-entware.sh` sets it for Entware only | `01-fixnan` (`0x00B330D1` on C5 2.0.7, no checks) |
| Clock | In the startup core (`ntpclient`) | `02-fixtime` (`rdate`) |
| Moonraker | `40-moonraker` (in `/usr/data`) | `20-msmr` (`moonrakerDaemon` and nginx in `/usr/prog`) |
| nginx | `45-nginx` (in `/usr/data`) | `20-msmr` |
| Touchscreen | `70-grumpyscreen` (grumpy-ff build) | not compared |
| Camera | `30-camera` (FlashForge's mjpg-streamer) | `30-camera` |
| Entware | `05-entware` | `05-entfix` |
| Klipper start | In the startup core | `10-klipper` |
| Updates | none | `99-opencreator-updater`, tunneled bridge |
| Toolhead board wake | Eboard start in the startup core (AD5X only) | not compared |
| Network | Ethernet, Wi-Fi, hotspot, static addresses, cable watch | Wi-Fi only |

## Worth taking from OpenCreator

- The Wi-Fi watchdog (USB reset)
- The camera script
- `power_loss_recovery` (from their `klipper-c5`)

## GrumpyScreen

OpenCreator's installer downloaded a legacy-NaN GrumpyScreen build without touch calibration. OpenAD5X uses the `grumpy-ff` build: NaN2008 and `GUPPY_CALIBRATE`. See [Touchscreen](touchscreen.md).
