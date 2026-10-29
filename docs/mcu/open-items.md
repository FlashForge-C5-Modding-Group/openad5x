# Open items

What is still unknown or not done on the MCU and host side.

## Mainboard

- The host GPIO numbers `NationsCommand` uses for the mainboard's BOOT0 and RESET. They could come from the tool's code or from an `strace` on the printer.
- `kalico-ad5x` has no `MACH_N32G455xE` or `xC` sub-variants (those come from xblax/klipper). What they change compared with the plain `MACH_N32G455` has not been checked.
- What the FlashForge-only `set_radar_*` commands are used for.

## Load cell

- Weighing and crash detection through the load cell on `ttyS7` are not implemented. Probing works: the trigger is a plain pin (PB3), and the load cell is tared and read with `H1` and `H7`. See [Bed load cell](../research/loadcell.md).

## Host

- The stock printer's Jinja2 and MarkupSafe versions without ZMod are not known (the dump comes from a ZMod printer).

## Moved elsewhere

These were open earlier and are done:

- Host Python, Entware, the compiler, the `c_helper.so` build and the boot script that sets the NaN byte and the `/opt` mount: see [Entware and Python](../architecture/entware-python.md).
- `ttyS3`: unused air-quality sensor code from another model, see [Power key](../architecture/power.md).

The IFS open questions are on [IFS hardware](../ifs/hardware.md).
