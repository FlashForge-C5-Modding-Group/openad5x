<div class="oc-hero" markdown>

# OpenAD5X

Open-source software for the FlashForge AD5X.

[Status and roadmap](status-and-roadmap.md) | [Project layout](project-layout.md)

</div>

OpenAD5X replaces FlashForge's closed programs on the AD5X with open-source ones. FlashForge's Linux stays as it is. The closed program being replaced is `firmwareExe`, which is the screen app and also runs most of the printer.

## What runs on the printer

- **Kalico** (Klipper) on the host and on the mainboard, toolhead board and IFS MCUs
- **Moonraker** and **Fluidd**
- **GrumpyScreen** on the touchscreen
- The **IFS** multi-colour feeder, run as a unit of **AFC** (Automated Filament Changer), with behaviour matched to the stock firmware: selector, feeding, purge chute, wipes, auto-load and unload
- The bed load cell for probing

## Where to read next

<div class="grid cards" markdown>

- **[Status and roadmap](status-and-roadmap.md)**

    What works, what is untested and what is open.

- **[IFS](ifs/index.md)**

    How the stock IFS and host behave, decoded from the stock firmware, and how ours matches.

- **[Architecture](architecture/index.md)**

    The plan: what firmwareExe does and how each part is replaced.

- **[Project layout](project-layout.md)**

    Which repository holds what.

</div>
