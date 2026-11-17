# What makes OpenAD5X different

## Kalico, not FlashForge's Klipper
Stock runs an old Klipper on Python 3.8, driven by FlashForge's closed `firmwareExe`. OpenAD5X runs
Kalico, a Klipper fork with more features, on the printer's computer and on every board, including the IFS.

## The IFS, decoded from stock
The IFS's behaviour was read out of FlashForge's own firmware, move by move: the cut, the purge chute,
the wipes, feeding, auto-load and unload. OpenAD5X runs it through AFC and matches it. The details are
under [IFS](ifs/index.md).

## Mainstream UIs
Fluidd, Mainsail and Moonraker come straight from their projects, not forked, so they update as soon as
updates come out.

## Full installer
Pick what you want before it installs: SoC or tunnelled, Fluidd or Mainsail, GrumpyScreen or not. The
installer can back up the printer first, and roll back to FlashForge's software from the same USB drive.

## Updates that keep your edits
Config updates are merged into your files instead of overwriting them, and new MCU firmware is flashed
to the boards by itself, like stock.

## Maintainable source
The code is split by job across [the repositories](project-layout.md) and is plain to read, so it's easy
to see what OpenAD5X does.

## Support over Discord
Feedback and support happen in one place, the [Discord](https://discord.gg/RsdkqDtfww).
