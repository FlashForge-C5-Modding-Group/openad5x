# Differences from OpenCreator

OpenAD5X follows [OpenCreator](https://github.com/FlashForge-C5-Modding-Group/OpenCreator) (Creator 5) where the printers allow, so the two can share work. The boot has the same structure, and these are the differences. It was last compared on 2026-10-30; check the `opencreator-fs` repository before relying on a row.

| Part | OpenAD5X | OpenCreator |
|---|---|---|
| Base folder | `/usr/data/openad5x` | `/usr/data/opencreator` |
| `firmwareExe` | Network from `Adventurer5M.json` (hotspot, Wi-Fi, ethernet with a cable watch, static addresses), no coprocessor | Wi-Fi watchdog (USB reset) and the SoC coprocessor |
| `startup.sh` | Starts the scripts in parallel | The same, and first runs the MCU flash the installer staged in `mcu-flash-pending` |
| NaN setting | `01-fixnan` sets the byte for Entware's binaries on kernel 2.0.1 | `01-fixnan` (`0x00B330D1` on C5 2.0.7) |
| Clock | `02-fixtime` (`rdate`) | `02-fixtime` (`rdate`) |
| Entware | `05-entfix` | `05-entfix` |
| SFTP | `06-sftp` patches dropbear the same way | `06-sftp` |
| Toolhead board wake | `08-mcu-wake`: the eboard only, started before Klippy, with the `eboard.flash` hook | `08-mcu-wake` for the C5's boards, started when Klippy cannot connect |
| Klipper start | `10-klipper`, which also links the AFC and IFS modules | `10-klipper`, with `oc-plugin sync` for the modules |
| Moonraker | `20-moonraker`, installed by the installer (Arksine on `python-hf`) | `20-msmr` (and nginx) |
| nginx | `25-nginx`: Entware's nginx, because the AD5X has none | The stock nginx in `/usr/prog` |
| Camera | `30-camera`: FlashForge's own mjpg-streamer command | `30-camera` with the C5 camera settings |
| Touchscreen | `40-grumpyscreen` (grumpy-ff build) | `40-grumpyscreen` |
| MCU flashing | `ad5x-mcu-flash`: mainboard and IFS live, eboard at the next power cycle | The installer flashes the four boards from an update package |
| Updates | Moonraker's update manager tracks `AD5X-FS`; nothing merges config changes yet | `99-opencreator-updater`, tunneled bridge |
| Plugins | none | `plugin-manager` |

## Worth taking from OpenCreator

- The Wi-Fi watchdog (USB reset)
- `power_loss_recovery` (from their `klipper-c5`)
- The updater that merges config changes

## GrumpyScreen

OpenCreator's installer downloaded a legacy-NaN GrumpyScreen build without touch calibration. OpenAD5X uses the `grumpy-ff` build: NaN2008 and `GUPPY_CALIBRATE`. See [Touchscreen](touchscreen.md).
