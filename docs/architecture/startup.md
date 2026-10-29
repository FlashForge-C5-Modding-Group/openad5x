# Startup

FlashForge's `/usr/prog/app_startup.sh` used to start `firmwareExe` and restart it every 10 s. On OpenAD5X that block is replaced by one line:

```sh
/usr/prog/openad5x/startup.sh > /usr/data/logs/openad5x.log 2>&1 &
```

A copy of the original `app_startup.sh` (the official 3.1.0 file, md5 `08ba2971...`) should be kept off the printer.

## Core and drop-ins

`startup.sh` is the core and runs a fixed order:

1. Toolhead board (eboard)
2. Klipper: Kalico through `/usr/data/kalico/start.sh`, or stock Klipper if that file is not executable
3. Network
4. Clock (in the background)
5. The drop-ins in `startup.d/`

The drop-ins are the optional parts. `*.sh` files in `/usr/data/openad5x/startup.d/` run one after another in name order, not in parallel. Each script returns quickly and starts its own long-running program in the background. Rename a script to `.off` to disable it. A failing script does not stop the others, and an empty folder or spaces in names are fine.

| Drop-in | What it does |
|---|---|
| `05-entware.sh` | Sets the legacy NaN byte, bind-mounts Entware on `/opt`, runs `rc.unslung start` |
| `30-camera.sh` | FlashForge's mjpg-streamer on port 8080 |
| `40-moonraker.sh` | Moonraker |
| `45-nginx.sh` | nginx, with Fluidd on port 80 |
| `70-grumpyscreen.sh` | GrumpyScreen with `DISPLAY_ROTATE=0` |

A `50-usb-automount.sh` is planned.

## Eboard flash hook

`startup.sh` has a one-time eboard flash hook. If `/usr/data/kalico-fw/eboard.flash` exists, it holds the path of a `.hex` to flash. The file is deleted after use, and the log is `/usr/data/logs/openad5x/eboard-flash.log`.

## Web access

Fluidd is at `http://<printer>/` through nginx, and Moonraker is on port 7125.

## Logs

| Log | Contents |
|---|---|
| `/usr/data/logs/openad5x.log` | `startup.sh`, with one line per drop-in and its exit code |
| `/usr/data/logs/openad5x/<name>.log` | Each drop-in |
| `moonraker.log`, `moonraker.out`, `nginx-error.log`, `grumpyscreen.log`, `mjpg-streamer.log` | The programs the drop-ins start |

## Clock

The printer has no battery clock and boots at 1970. `startup.sh` runs `clock_sync` in the background: `/usr/prog/ntpclient -c 1 -s -h pool.ntp.org` every 5 s until the year is 2024 or later (at most 5 minutes), then logs `clock: <date>`.

`firmwareExe` ran `ntpclient` without `-c`, which leaves it running as a daemon that re-syncs every 600 s. `-c 1` sets the time once and exits.

The clock matters because with a 1970 date HTTPS fails with "certificate is not yet valid".

## Tested

Power-cycle tests passed on 2026-10-10 (eboard, Klipper with both MCUs configured, network, Moonraker, nginx) and on 2026-10-11 (the clock: set, no `ntpclient` left running, no certificate errors).
