# Touchscreen

The touchscreen app is GrumpyScreen, built for the FlashForge hardware by [`grumpy-ff`](https://github.com/FlashForge-C5-Modding-Group/grumpy-ff).

## The grumpy-ff build

`FlashForge-C5-Modding-Group/grumpy-ff` builds GrumpyScreen automatically:

- GitHub Actions checks the upstream GrumpyScreen's latest release every 6 hours, or on a manual run with an optional tag and a force-rebuild option (see [Build inputs](packages.md#build-inputs)).
- It builds that exact commit unchanged and releases `<tag>-ff` with `grumpyscreen-ff.tar.gz`.
- Build logs are on the `build-logs` branch (`latest.log` and one file per run).

The build:

- Toolchain: `musl-cross-make`, GCC 12.4, musl 1.2.4, with the defaults mips32r2, NaN2008, FP64 and odd-spreg. That is the same ABI as FlashForge's own binaries (`readelf` on `firmwareExe` and `/lib/libc.so.6` shows flags `0x70001405`, FP ABI 64-bit FPU, glibc `/lib/ld-linux-mipsn8.so.1`).
- Static, built with `GUPPY_CALIBRATE` (on-screen touch calibration).
- The build fails unless `readelf` shows static, mips32r2, nan2008 and FP64.

The release contains `grumpyscreen`, the upstream default `grumpyscreen.cfg` (unchanged), `start.sh`, and `VERSION` (upstream tag and commit), all owned by `root:root`.

## On the printer

| | |
|---|---|
| Install path | `/usr/data/grumpyscreen` (v2.0.0-323-ff when installed) |
| Started by | `startup/scripts/40-grumpyscreen.sh` with `DISPLAY_ROTATE=0` |
| Rotation | Upstream's default `display_rotate: 3` is for the K1 and is sideways on the AD5X, so rotation 0 is used |
| Log | `/usr/data/logs/grumpyscreen.log` |
| Touch driver | Stock (`app_startup.sh` loads it with `actrue` 0 to 4096 and `y_flip=1`) |
| Calibration | Done on screen at the first start, saved in `/usr/data/grumpyscreen/calibration.json` |
| MMU panel | If AFC is installed (`/usr/data/AFC-Klipper-Add-On`) and the config says `backend: none`, the drop-in sets the backend to `afc` |

`start.sh` uses the input device with "Touchscreen" in its name (the same rule as FlashForge's `app_startup.sh`) and passes it in `LVGL_EVDEV_DEV`, because the event number depends on driver load order. On the AD5X, `event0` is `md-gpio-keys` and `event1` is the TSC2007 touchscreen.

To update, download the new release and unpack it with `gunzip -c | tar -xf - -C /usr/data`. `calibration.json` is not in the tarball, so your calibration is kept.

## Screen facts

- `/dev/fb0`, 32 bpp, virtual size 800x960 (two 800x480 buffers), framebuffer rotation 0
- Backlight: `/sys/class/backlight/backlight_gpio0` (on and off only)
- CPU: Ingenic X2600 (XBurst II), mips32r2/r5, MSA

## Why the upstream release is rebuilt

The upstream GrumpyScreen release is MIPS32r1, FPXX and legacy NaN. The X2600 kernel (no `ieee754=` on the command line) refuses it.

The first workarounds, on 2026-10-11, were a one-byte `e_flags` NaN2008 patch, the kernel NaN byte (`busybox devmem 0x00a130d1 8 1` on kernel 2.0.1; on the C5 it is `0x00a130d1` for 2.0.5 and 2.0.6, and `0x00b330d1` for 2.0.7) set by a `10-nan-relaxed.sh` drop-in, and a touch-scale change in the `tsc2007` values. All of them were dropped once `grumpy-ff` built a NaN2008 binary. A power-cycle test passed on 2026-10-17 with the NaN byte at 0.
