# Status and roadmap

Last updated 2026-10-28. Status as seen on a real AD5X.

## What works

| Area | Status | Notes |
|---|---|---|
| Kalico on the host and the mainboard, toolhead board and IFS MCUs | <span class="oc-status ok">Working</span> | IFS runs Kalico firmware over its serial port |
| IFS as an AFC unit (select, home, feed) | <span class="oc-status ok">Working</span> | Selector homes at the stock speed |
| Colour change (cut, unload, lane-pushing purge, load) | <span class="oc-status ok">Working</span> | A 53-minute 4-colour print finished with 19 tool changes, each about 60 s |
| Purge chute entry and exit, wipes | <span class="oc-status ok">Working</span> | Same moves as stock: in along X then Y, out along Y first |
| Flush at the start of a print | <span class="oc-status ok">Working</span> | Done even when AFC thinks the first lane is already loaded |
| Auto-load when a spool is inserted (empty toolhead) | <span class="oc-status ok">Working</span> | Feeds to the toolhead sensor, parks 100 mm back |
| Bed load cell probing | <span class="oc-status ok">Working</span> | Probe `z_offset` is -0.25, as stock |

## Deployed, not yet tested on hardware

| Area | Status | Notes |
|---|---|---|
| Auto-load while another lane is in the toolhead | <span class="oc-status test">Testing</span> | Stock feeds a fixed 650 mm then parks 100 mm back; ours does the same |
| Unload at the end or cancel of a print | <span class="oc-status test">Testing</span> | Has an on/off switch in the web UI filament sensors list (`end_unload`) |
| First-layer height with `z_offset: -0.25` | <span class="oc-status test">Testing</span> | |

## Open

| Area | Status | Notes |
|---|---|---|
| IFS serial link noise | <span class="oc-status bad">Open</span> | Invalid and retransmitted bytes keep climbing on the IFS link |
| Silk sensor calibration for lanes 1 to 3 | <span class="oc-status partial">Partial</span> | `IFS_SILK_CALIBRATE` exists; lane 4 is done |
| Toolhead sensor idle value | <span class="oc-status partial">Partial</span> | Reads about 0.32 when empty, close to the 0.30 "present" limit |
| Colour-based flush volumes | <span class="oc-status plan">Planned</span> | The purge is a fixed 90 mm per flush |
| Installer support | <span class="oc-status plan">Planned</span> | Through `touchscreen-installer` (branch `ad5x`) |
| Documentation site logo and branding | <span class="oc-status plan">Planned</span> | |
