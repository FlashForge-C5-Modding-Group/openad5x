# MCU development

Goal: run Kalico on the host and on both MCUs, so the IFS can join as a Kalico MCU (see [IFS](../ifs/index.md)).
A Klipper/Kalico host only talks to MCUs built from the same code, so host, mainboard, eboard and IFS switch together.

| Page | What is in it |
|---|---|
| [Boards, pins and power](boards.md) | The three boards and their MCUs, the stock pin maps, and the eboard power and pcb_fan notes |
| [Clock](clock.md) | How the stock firmware sets the clock, and what Kalico has to change |
| [Flashing and test builds](flashing.md) | Flashing the mainboard and eboard, the bootloaders, test builds and what was flashed |
| [Kalico build and kiln-os](kalico-build.md) | Kalico build configs, the FlashForge-only commands, and notes from kiln-os |
| [Host side](host.md) | FlashForge's host-side changes, and Kalico's Klippy on the AD5X: Python, `c_helper.so`, packages |
| [Open items](open-items.md) | What is still unknown or not done |
