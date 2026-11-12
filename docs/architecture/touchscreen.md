# Touchscreen

The touchscreen app is GrumpyScreen, the same release as the Creator 5: [`FlashForge-C5-Modding-Group/grumpyscreen`](https://github.com/FlashForge-C5-Modding-Group/grumpyscreen). The installer's `30-install-grumpyscreen` downloads the latest release binary and adds a `[update_manager grumpyscreen]` entry to `moonraker.conf`, so it updates from Fluidd.

## On the printer

| | |
|---|---|
| Install path | `/usr/data/grumpyscreen` (`grumpyscreen`, `grumpyscreen.cfg`, `release_info.json`; release 0.0.4 when installed) |
| Started by | `startup/scripts/40-grumpyscreen.sh` with `DISPLAY_ROTATE=0`, restarted 3 s after it stops |
| Config | `/usr/data/openad5x/klipper/config/grumpyscreen.cfg`, copied on the first start from `/usr/data/grumpyscreen/grumpyscreen.cfg` (from AD5X-FS), editable from Fluidd |
| Log | `/usr/data/logs/grumpyscreen.log` |
| Touch input | The input device with `goodix` or `touch` in its name (the TSC2007, `event1`), passed in `LVGL_EVDEV_DEV` |
| Calibration | None in this build: it uses the driver's numbers as screen pixels |
| Touch driver | `40-grumpyscreen.sh` reloads `tsc2007_touch.ko` once per boot with the panel's real touch window, X 309 to 3765 and Y 705 to 3447, mapped to 800x480 with `y_flip=1`. Stock loads it with 0 to 4096, which squeezes touches toward the centre |
| MMU panel | If `printer.cfg` includes `AFC/` and the config says `backend: none`, the backend is set to `afc` |

## Screen facts

- `/dev/fb0`, 32 bpp, virtual size 800x960 (two 800x480 buffers), framebuffer rotation 0
- Backlight: `/sys/class/backlight/backlight_gpio0` (on and off only)
- CPU: Ingenic X2600 (XBurst II), mips32r2/r5, MSA

## History

Until November 2026 OpenAD5X used `grumpy-ff`, a NaN2008 rebuild of the upstream GrumpyScreen release with `GUPPY_CALIBRATE`, because the upstream release is MIPS32r1, FPXX and legacy NaN. The X2600 kernel (no `ieee754=` on the command line) refuses it.

The first workarounds, on 2026-10-11, were a one-byte `e_flags` NaN2008 patch, the kernel NaN byte (`busybox devmem 0x00a130d1 8 1` on kernel 2.0.1; on the C5 it is `0x00a130d1` for 2.0.5 and 2.0.6, and `0x00b330d1` for 2.0.7) set by a `10-nan-relaxed.sh` drop-in, and a touch-scale change in the `tsc2007` values. All of them were dropped once `grumpy-ff` built a NaN2008 binary. A power-cycle test passed on 2026-10-17 with the NaN byte at 0.
