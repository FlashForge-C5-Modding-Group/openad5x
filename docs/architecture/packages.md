# Packages and builds

Moonraker and Fluidd are packaged as two tarballs and built on a PC. The build scripts are in `AD5X-FS`, under `build/`.

!!! note "Previous layout"
    This is how the test printer got Moonraker and the web UI. The [installer](../installer.md) no longer uses these tarballs: it clones Arksine's Moonraker into `/usr/prog/moonraker` with an environment on `python-hf`, installs Fluidd from its latest release, and uses Entware's `nginx-ssl`. The packages and their tested details are kept here until the new way has run on a printer.

## Moonraker package (`moonraker-ad5x.tar.gz`)

Moonraker is pinned at commit `abd2026b90` and reports version `v0.9.3-abd2026`. Later commits raise the Python requirements (`3ea83163b0`, `paho-mqtt` 2.1.0 and others) beyond what this Python can use.

It runs on FlashForge's Python 3.8.2:

| Variable | Value |
|---|---|
| `PYTHONPATH` | `/usr/data/moonraker-env/site-packages` |
| `LD_LIBRARY_PATH` | `/usr/data/moonraker-env/lib` plus FlashForge's libraries |
| `SSL_CERT_FILE` | the `certifi` bundle in `site-packages` |

What goes into the package:

- **Pure-Python packages** from an existing Moonraker environment built for this ABI (`pip`, `setuptools` and `virtualenv` left out).
- **From the Creality Ender-3 V3 firmware** `F001_V1.2.3.23`, which has the same MIPS NaN2008/FP64 ABI: the `sqlite3` package, the `_sqlite3` module, `libsqlite3.so.0` and `libsodium.so.23`.
- **From FlashForge's Python:** `lmdb`, `pillow` 7.0.0, `streaming-form-data` 1.8.1 and `pyserial`.

`moonraker.conf` has no `[update_manager]`: Moonraker must not update itself.

## Web package (`fluidd-ad5x.tar.gz`)

nginx 1.17.7 comes from the same Ender-3 V3 firmware. It needs `libpcre.so.1` and `libz.so.1`, which are both on the AD5X.

Port 80 serves `/usr/data/fluidd` and passes `/websocket`, `/printer`, `/api`, `/access`, `/machine` and `/server` to Moonraker. There is a harmless startup alert: nginx tries its built-in `/var/log/nginx/error.log` before it reads `nginx.conf`.

## Build inputs

Where the outside parts of each build come from:

| Input | Source |
|---|---|
| Moonraker source | `https://codeload.github.com/Arksine/moonraker/tar.gz/<MR_COMMIT in build.py>` |
| Moonraker environment (pure-Python packages) | Simple AF's `k1/moonraker-env.tar.gz` |
| `sqlite3`, `libsodium`, nginx, `mime.types` | `F001_V1.2.3.23.ingenic`, file `images/rootfs.squashfs` (unpacked with 7-Zip) |
| Fluidd | A Fluidd release (v1.37.6 used) |
| GrumpyScreen | The upstream GrumpyScreen release that `grumpy-ff` rebuilds |

## Building the packages

Downloads and extracted files are not kept in the repository. Put them in a throwaway folder next to a copy of `build.py`.

### `moonraker-ad5x.tar.gz`

Files needed:

- `<folder>/dl/moonraker.tar.gz` (the Moonraker source, from the table above)
- argument 1: the Moonraker environment archive
- argument 2: a folder with the files extracted from the `F001` rootfs:
    - `usr/lib/libsqlite3.so.0.8.6`
    - `usr/lib/libsodium.so.23.3.0`
    - `usr/lib/python3.8/sqlite3/*.py`
    - `usr/lib/python3.8/lib-dynload/_sqlite3.cpython-38-mipsel-linux-gnu.so`

```sh
python build.py <moonraker-env.tar.gz> <f001 folder>
```

### `fluidd-ad5x.tar.gz`

Files needed:

- `<folder>/nginx.conf`
- `<folder>/dl/fluidd.zip` (the Fluidd release)
- argument 1: the same `F001` folder, plus `usr/sbin/nginx` and `etc/nginx/mime.types`

```sh
python build.py <f001 folder>
```

## Installing

Stream the tarball to the printer with `gunzip -c | tar -xf - -C /usr/data` (busybox `tar` has no `-z`). Copy `moonraker.conf` to `/usr/data/config/moonraker.conf`.
