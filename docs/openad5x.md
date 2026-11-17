# OpenAD5X

OpenAD5X makes the AD5X's host software, MCU firmware, IFS and configuration
maintainable as one community-developed stack, for more features and more open software
than stock. It's in public alpha; see [Installation and safety](installation-and-safety.md).

The work is split between
[kalico-ad5x](https://github.com/FlashForge-C5-Modding-Group/kalico-ad5x) for Kalico, the AD5X
MCU code and the AFC modules,
[AD5X-FS](https://github.com/FlashForge-C5-Modding-Group/AD5X-FS) for the printer files,
configuration and boot, and the
[touchscreen-installer](https://github.com/FlashForge-C5-Modding-Group/touchscreen-installer)
(branch `ad5x`) for installing. It follows [OpenCreator](https://opencreatorcfw.github.io/) for
the Creator 5 where the printers allow; see [Differences from OpenCreator](architecture/opencreator.md).

## What it aims to support

| Area | Goal | Status |
| --- | --- | --- |
| Base software | Kalico on the host and on the mainboard, toolhead board and IFS. | <span class="oc-status ok">Finished</span> |
| IFS | Run the four-lane IFS as an AFC unit, matched to the stock firmware. | <span class="oc-status ok">Finished</span> |
| Installation and updates | Install from USB; update from Fluidd or Mainsail with config merging. | <span class="oc-status test">Testing</span> |
| Web and touchscreen | Fluidd or Mainsail, and GrumpyScreen on the touchscreen. | <span class="oc-status ok">Finished</span> |

For what's finished and what's still open in detail, see [Status and roadmap](status-and-roadmap.md)
and [Features](features.md).
