# OpenAD5X features

<span class="oc-status ok">Finished</span> works on a printer &nbsp;
<span class="oc-status test">Testing</span> in testing or untested

| Feature | Implementation | Description |
| --- | --- | --- |
| Kalico everywhere | <span class="oc-status ok">Finished</span> | Kalico on the printer's computer and on the mainboard, toolhead board and IFS. The installer flashes the boards. |
| IFS through AFC | <span class="oc-status ok">Finished</span> | The four-lane IFS as an AFC unit: lane select, feeding, the stock cut, purge chute and wipes, load and unload. Tool commands `T0` to `T3`. |
| IFS auto-load | <span class="oc-status ok">Finished</span> | Insert a spool and it feeds to the toolhead sensor and parks, as stock. |
| Unload at print end | <span class="oc-status test">Testing</span> | Unloads at the end or cancel of a print; the `end_unload` switch turns it off. |
| Load cell probing | <span class="oc-status ok">Finished</span> | The bed load cell homes Z and probes the bed mesh, with a tare before every probe as stock. |
| Adaptive mesh switch | <span class="oc-status ok">Finished</span> | Mesh only where the print is, or the full bed; see [How to toggle features](toggle-features.md). |
| Input shaper and PID in one go | <span class="oc-status ok">Finished</span> | `ADX_QUICK_START` runs input shaper with the built-in accelerometer, nozzle and bed PID, then saves. |
| Stock-style pause and resume | <span class="oc-status ok">Finished</span> | Pause parks at the chute; resume heats back up, flushes and brushes like stock. |
| Pause at a layer | <span class="oc-status ok">Finished</span> | `SET_PAUSE_NEXT_LAYER` and `SET_PAUSE_AT_LAYER`, and Fluidd's and Mainsail's layer pause. |
| Full WebUI support | <span class="oc-status ok">Finished</span> | Fluidd or Mainsail with Moonraker; the touchscreen is optional. |
| GrumpyScreen | <span class="oc-status ok">Finished</span> | Touchscreen UI with extrude, retract, load and jog; the backlight turns off when it sleeps. |
| Timelapse | <span class="oc-status ok">Finished</span> | Moonraker Timelapse, installed by the installer. |
| SFTP over SSH | <span class="oc-status ok">Finished</span> | Transfer and manage files with SFTP. |
| Config updates that keep your edits | <span class="oc-status test">Testing</span> | The update merges the new config templates into your files; clashing edits are left in a `.conflict` file. |
| MCU firmware updates | <span class="oc-status test">Testing</span> | A new MCU firmware version in an update is flashed to the boards by itself, like stock. |
