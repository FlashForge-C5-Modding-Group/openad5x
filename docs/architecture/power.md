# Power key

The AD5X only has a hard power switch, so none of the power-key code is needed. `firmwareExe`'s power-key code is shared with other FlashForge models:

1. `MainWindow::powerKeyChecking` finds the input device named `md-gpio-keys` (`keyboard_gpio_add.ko`, PB11, `KEY_POWER2`) and starts `PowerKeyThread` on it.
2. A key press calls `MainWindow::doPowerOff()`: it wakes the screen and asks "Do you want to turn off the printer ?". On Yes it calls `gpio_out(44, 0)`.

Nothing is wired to PB11 on the AD5X, so this never fires.

The same `GPIO 44 = 0` is used by the screen's power-off, by power-off after a print (`printCompletedPowerOff`) and by FlashForge's app (`doPowerOff(string,int)`). What GPIO 44 does on the AD5X is unknown. Reproducing it is optional and not needed for printing.

## Not needed

`/dev/ttyS3` is unused air-quality sensor code from another model. `firmwareExe` never starts it.
