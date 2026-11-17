# Slicer configuration for OrcaSlicer

Settings for printing on OpenAD5X from OrcaSlicer, starting from the FlashForge AD5X profile.

## Print profile

- [x] Under **Others → G-code output**, switch `Label objects` and `Exclude objects` **on**.

    This lets the adaptive mesh probe only where the print is, and lets you exclude objects from
    Fluidd/Mainsail.

## Printer profile

### Connection

- [x] Click the Wi-Fi connect button (next to the printer) and change the host type to `Moonraker`.
- [x] Remove any serial numbers or API keys.

### Printer settings

- [x] **Printer Agent:** switch to `Moonraker`.
- [x] **Use 3MF instead of G-code:** switch `off`.

### Machine G-code

- [x] **Machine start G-code:** set it to this:

```
SET_PRINT_STATS_INFO TOTAL_LAYER=[total_layer_count]
START_PRINT EXTRUDER_TEMP=[nozzle_temperature_initial_layer] BED_TEMP=[bed_temperature_initial_layer_single]
G0 Y219.6
G1 X130 E5
```

`START_PRINT` heats, homes, probes the mesh and waits at X20 Y219.6, Z0.3; the last two lines draw
the prime line along the back edge.

- [x] **Machine end G-code:** set it to `END_PRINT`.

    It unloads the filament (unless the `end_unload` switch is off), turns the heaters off, lifts
    the nozzle and parks.

- [x] **Change filament G-code:** set it to `T[next_extruder]`.

    AFC runs the IFS colour change for `T0` to `T3`.

- [x] **Layer change G-code:** add `SET_PRINT_STATS_INFO CURRENT_LAYER={layer_num + 1}`.

    Fluidd's and Mainsail's layer pause and `SET_PAUSE_AT_LAYER` need it.

- [x] **Layer change G-code (optional, for timelapses):** add `TIMELAPSE_TAKE_FRAME` on its own
  line, so timelapse takes a frame at every layer.
