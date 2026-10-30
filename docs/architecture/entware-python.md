# Entware and Python

Kalico builds `c_helper.so` on the printer, so the printer needs a compiler and a recent Python. Entware provides gcc, and a hard-float Python 3.13 provides the interpreter. The method is the same as the one in the Creator 5 group's `touchscreen-installer` (`common/install-entware.sh`).

CPU: Ingenic XBurst II, isa mips32r2 and mips32r5, MSA.

## Entware

Installed on 2026-10-23.

```sh
busybox devmem 0x00a130d1 8 1        # legacy NaN byte (kernel package 2.0.1)
mkdir -p /usr/data/bin/opt
mount --bind /usr/data/bin/opt /opt
wget -O - http://bin.entware.net/mipselsf-k3.4/installer/generic.sh | sh
/opt/bin/opkg install gcc            # OpenWrt GCC 8.4.0, about 35 MB
wget -O - http://bin.entware.net/mipselsf-k3.4/include/include.tar.gz | gunzip -c | tar x -C /opt/include
```

- The `mipselsf-k3.4` packages are glibc 2.27 (loader `ld.so.1`). The printer has glibc 2.33.
- `/usr/data` free space: 2.2 GB before, 1.7 GB after.
- Packages: gcc 8.4.0-8, libgcc 8.4.0-12, binutils 2.45.1-1, libc 2.27-12.
- `gcc --version` also prints "unrecognized command line option" for `-msoft-float -mllsc -mno-shared -mabi=32` and exits 0.
- gcc needs `/opt/bin` on `PATH`, because it runs `as` and `ld` from there.

### The empty specs file

The gcc install leaves `/opt/lib/gcc/mipsel-openwrt-linux-gnu/8.4.0/specs` as a 0-byte file (`-rw-------`). When a `specs` file exists, the driver reads it instead of setting up its built-in specs. No spec then claims any option, so every option (`-O2`, `-g`, `-Wall`, even its own `-msoft-float -mllsc -mno-shared`) is "unrecognized" and nothing compiles. `cc1` and Entware's libc were fine (`strncmp`, `strcmp` and `memcmp` tested: 0 wrong out of 35376).

Fix: `mv specs specs.empty`. It is unknown why the install writes it empty. `opkg install --force-reinstall gcc` recreates it, so check after any gcc reinstall or upgrade.

### Test

Plain `gcc -O2 -Wall -g -c` works. Through the `python-hf` wrapper (`PATH=/usr/data/python-hf/cc/bin:$PATH:/opt/bin`), `gcc -Wall -g -O2 -shared -fPIC` builds a `.so` with flags `0x70001407` (nan2008, mips32r2, FP ABI hard float 64-bit FPU), needing `libpthread`, `libc` and `libm`, with RPATH `/usr/data/python-hf/lib:/opt/lib`. A Python 3.13 `cffi` `dlopen` and call works.

## Python 3.13

Installed on 2026-10-23 at `/usr/data/python-hf` from the `opencreator-fs` release `python-3.13-hardfloat-r2`, file `python-hf-c5.tar.gz` (sha256 `30989fdb8cc353691574c21d75af33287e8b164d043c0a32ed87dc58637bc3dc`, checked on the printer).

- The tarball was copied with `pscp -scp` (the printer has no `sftp-server`) and unpacked with `gunzip -c | tar x` (busybox `tar` has no `z`).
- Python 3.13.9 runs, and `cffi`, `greenlet`, `jinja2`, `markupsafe`, `numpy` and `serial` import. `markupsafe` has no package metadata (`markupsafe.__version__` fails), which Klippy does not need.
- `cc/bin/gcc` is a wrapper for Kalico's `c_helper.so` build. It calls `/opt/bin/gcc` with `-mips32r2 -mhard-float -mfp64 -mnan=2008` and its own glibc headers and `crt` files. This works since the specs fix. Klippy needs `PATH=/usr/data/python-hf/cc/bin:$PATH:/opt/bin` to build `c_helper.so`.

### `c_helper.so` test

The `kalico-ad5x` `klippy/chelper` folder, copied to `/tmp/chelper-test`, with `chelper.get_ffi()` under `python-hf` and that `PATH`: it builds `c_helper.so` in about 46 s (305 KB, `0x70001407` nan2008 mips32r2, FP ABI hard float 64-bit FPU), loads, and `trapq_alloc()` and `trapq_free()` work.

## At boot

`01-fixnan.sh` sets the NaN byte and `05-entfix.sh` bind-mounts `/opt` and runs `/opt/etc/init.d/rc.unslung start` (the previous boot's `startup.d/05-entware.sh` did both). A power-cycle test with the previous boot passed on 2026-10-23: `/opt` was mounted, gcc was there, and the NaN byte was `0x01`.

The NaN byte is needed again because the old `10-nan-relaxed.sh` was dropped on 2026-10-17 (GrumpyScreen from `grumpy-ff` does not need it), but Entware's binaries do. The byte and the bind mount are lost on reboot, which is why a boot script sets them.
