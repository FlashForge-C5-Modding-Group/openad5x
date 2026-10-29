# Host side

## FlashForge's host-side changes

`firmwareExe` opens `ttyS2`, `ttyS3`, `ttyS4` (IFS), `ttyS5` and `ttyS7` (load cell).

FlashForge replaced these Klippy files in the 3.1.6 software package:

| File | What it adds |
|---|---|
| `query_adc.py` | `QUERY_ADC`, `GET_FILAMENT_VALUE`, `GET_CUT_VALUE` (eboard PA3 and PA2) |
| `virtual_sdcard.py` | `SDCARD_CLEAR_REFUELLING`, `SDCARD_SET_CHANNEL`, `SDCARD_ENABLE_FFM` (IFS print integration with `firmwareExe`) |
| `extruder.py`, `exclude_object.py` | Modified versions |

There is also an extra module, `extras/bl24c16f.py` (EEPROM).

## Kalico's Klippy on the AD5X

- CPU: Ingenic X2600, mips32r2, NaN2008, FP64. glibc 2.33 (rootfs `lib/ld-2.33.so`, `lib/libc-2.33.so`, `/lib/ld-linux-mipsn8.so.1`). The stock printer has no compiler.
- FlashForge's Python is `/usr/prog/Python-3.8.2`. Moonraker already runs on it.
- The Kalico source is `kalico-ad5x` (FlashForge-C5-Modding-Group, from KalicoCrew upstream).

### Python version

Klippy from `kalico-ad5x` does not start on Python 3.8:

- `pyproject.toml` says `requires-python = ">=3.9"`.
- `printer.py` calls `compat.install()` on every start, and that uses `str.removeprefix` (3.9 and later) in `compat.py`.
- `configfile.py` also uses `removeprefix` (for Python script config values), and some extras use runtime `list[...]` and `tuple[...]` annotations without `from __future__ import annotations`: `extras/nozzle_cleanup.py`, `extras/probe_eddy_current.py`, `extras/load_cell/ads1220.py` and `extras/load_cell/hx71x.py`.

So the host needs Python 3.9 or newer, built for mips32r2, NaN2008 and FP64, or Klippy would have to be patched for 3.8. OpenAD5X uses the first option: the hard-float Python 3.13 build described below, installed as described in [Entware and Python](../architecture/entware-python.md).

### The Python 3.13 hard-float build

From the `opencreator-fs` release `python-3.13-hardfloat-r2` (2026-10-16), asset `python-hf-c5-release.zip` (which unpacks to `python-hf-c5.tar.gz`). It is "meant only for FlashForge devices, such as the Creator 5/Pro and AD5X".

- **Contents (BUILDINFO-c5):** Python 3.13.9 with prefix `/usr/data/python-hf`, numpy 2.2.2, greenlet 3.3.2 and cffi 2.0.0. Built with the Ingenic MIPS GCC 12.1 Release 6.0.0 toolchain (xburst2, glibc 2.33), from the C5's Kalico fork at commit `3250f3bff229276f52a5e4c2d0ce1c09b8fc0ddb`. The AD5X uses `kalico-ad5x`, not that fork.
- **ABI:** `bin/python3.13` has flags `0x70001405`, NaN2008, FP64, and interpreter `/lib/ld-linux-mipsn8.so.1`, the same as `firmwareExe`. `lib/libpython3.13.so.1.0` needs up to `GLIBC_2.33`, which matches the AD5X rootfs.
- **Packages:** `cffi`, `greenlet`, `jinja2`, `markupsafe`, `numpy`, `pycparser`, `serial` (pyserial) and `dbus_fast`: all the Kalico host packages.
- **Own libraries:** libffi, libssl and libcrypto 3, libsqlite3, liblzma, libbz2, libjpeg, libsodium, libatomic and libgcc_s.
- **`cc/bin/gcc`:** a shell wrapper around Entware's gcc (`${ENTWARE_GCC:-/opt/bin/gcc}`). It adds `-mabi=32 -mips32r2 -mhard-float -mfp64 -mnan=2008` and the bundled glibc headers and `crt` files (`cc/lib`, `cc/include`), so Klippy can build `c_helper.so` on the printer. It needs Entware's gcc in `/opt`.

### `c_helper.so`

`klippy/chelper/__init__.py` `get_ffi()` compiles `c_helper.so` with `gcc` on the first start, and again whenever the C sources are newer than the `.so` (`check_build_code`). The sources are `pyhelper.c serialqueue.c stepcompress.c steppersync.c itersolve.c trapq.c pollreactor.c` plus the kinematics files in `SOURCE_FILES`.

With Entware's gcc and the wrapper above, the printer builds it itself in about 46 s (305 KB, NaN2008, FP64). Without a compiler it would have to be cross-built (glibc, mips32r2, NaN2008, FP64, `-Wall -g -O2 -shared -fPIC`) and shipped with a newer modification time than the sources.

### Python packages

This is why FlashForge's own Python 3.8.2 cannot be used for Kalico, even apart from the version check:

| Package | Kalico (Python below 3.12) | FlashForge has |
|---|---|---|
| cffi | 1.15.1 | 1.13.1 |
| greenlet | 2.0.2 | 3.0.3 |
| Jinja2 | 3.1.6 or newer | 2.10.3 and 3.1.2 (3.1.2 may come from ZMod, the dump is from a ZMod printer) |
| markupsafe | 2.1.5 | 1.1.1 and 2.1.1 (the same caveat) |
| numpy | about 2.0 (Python 3.9) | 1.16.4 |
| pyserial | 3.4 | 3.4 |

With a newer Python these packages have to be built for it too: `cffi`, `greenlet`, `markupsafe` and `numpy` have C parts. The `python-hf` build includes them. The FlashForge packages are in the factory image at `usr/prog/Python-3.8.2/lib/python3.8/site-packages`.
