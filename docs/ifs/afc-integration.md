# IFS in AFC

The IFS runs as a unit of [AFC](https://github.com/ArmoredTurtle/AFC-Klipper-Add-On) (Automated Filament Changer). AFC is only the framework: `AFC_IFS.py` makes the IFS behave like the stock firmware. The options, flows and commands are in `config-docs/IFS.md` in `AD5X-FS`. This page records how the unit is set up and why.

## Installing AFC on the printer

AFC was copied from the upstream repository (commit `5ea84ea`) to `/usr/data/AFC-Klipper-Add-On`, with LF line endings and no `.git`. The upstream `install-afc.sh` expects a standard Klipper host, so its steps were done by hand:

- `extras/*.py` (except `__init__.py`, 31 files) is symlinked into `/usr/data/kalico/klipper/klippy/extras/`.
- `/usr/data/ad5x-afc/AFC_IFS.py` and `AFC_Hardware-IFS.cfg` are added, and `AFC_IFS.py` is symlinked into `klippy/extras/`.
- `/usr/data/config/kalico/AFC/` holds `AFC.cfg`, `AFC_Macro_Vars.cfg`, `macros/`, an empty `mcu/` and `AFC_Hardware-IFS.cfg`.
- `[include AFC/*.cfg]` goes in `printer.cfg` above the `SAVE_CONFIG` block.
- `VarFile` in `AFC.cfg` is `/usr/data/config/kalico/AFC/AFC.var`. The message `AFC.var.unit not found` on the first start is normal: AFC creates it on the first save.

Things to know:

- No extra Python packages are needed: AFC imports only the standard library and Klippy modules.
- Kalico's ADC API is `setup_adc_sample(sample_time, sample_count)`, not `setup_minmax`.
- **A change to a Python module needs a full Klippy process restart.** `RESTART` and `printer/restart` keep the old module.
- `[AFC_extruder extruder]` has no `pin_tool_start`, because the toolhead filament sensor is analog (eboard PA3). The sensor is declared with `u1_filament_sensor_name: fill_sensor`.
- The unit section has no `hub`: a unit `hub` must name an `[AFC_hub]`. The lanes and both `AFC_stepper` sections use `hub: direct`.
- Lanes without a `load` pin start with `load_state` True. `AFC_IFS` applies the first silk reading so lanes show their real state.
- AFC's lane move speeds are set to the stock feed speed (20 mm/s). The AFC defaults were 50 and 150 mm/s.
- Command and macro names must be letters and underscores only. Klipper's parser reads the command as the first letter run plus the digits after it, so a command called `AD5X_CUT` is read as `AD5` and never dispatches. That is why the commands are named `ADX_...`.

## Motors

| | Feed | Selector |
|---|---|---|
| Step | `PA0` | `PA7` |
| Direction | `PA1` (positive = into the IFS toward the printer) | `PA6` (positive = home seek, count up) |
| Enable | `PA5`, active low | `PB1`, active low |
| TMC UART | `PA3` / `PA2` | `PC5` / `PC4` |
| Microsteps | 8 | 8 |
| Distance | `rotation_distance: 4.655` (343.696 steps/mm) | `rotation_distance: 360`, 2048 full steps per turn |

- The first version of the pin table used swapped helper names, so every output polarity was wrong and neither motor was ever enabled. The table above comes from the stock motor table.
- `SET_STEPPER_ENABLE` followed by `DUMP_TMC REGISTER=IOIN` is not a reliable check of the enable polarity here, because the reads lag the enable.
- The stock firmware runs the drivers in spreadCycle. In Kalico `stealthchop_threshold: 0` means stealthChop at all speeds (any value sets `en_pwm_mode`), so there is no `stealthchop_threshold` line. In stealthChop the feed driver showed `ola=1 olb=1` and the motor did not turn.
- Steps are single-edge (`step_pulse_duration: 0.000002`), as in stock (`CHOPCONF dedge=0`).

### Driver current

The clone drivers deliver far less current than spec in `vsense=1`. Kalico encodes 0.138 A as `vsense=1`, CS 17, and with that the selector clicked over every cam lobe and the feed skipped steps at 20 mm/s. The stock registers (`vsense=0`, IRUN 9, the same nominal current) run cleanly. Kalico's TMC2209 helper never drops to `vsense=0`, so `kalico-ad5x`'s `tmc2209.py` accepts raw `driver_<NAME>` fields, and the config sets the stock registers directly: `driver_VSENSE: 0`, `driver_IRUN: 9`, `driver_IHOLD: 0`, `driver_SHAFT: 1`, `driver_INDEX_OTPW: 1` and `driver_TPWMTHRS: 0`, besides the chopper settings. See the table in [Stock IFS firmware](stock-firmware.md#tmc-driver-setup).

## The feed motor and the extruder

AFC enables the lane's drive motor and syncs it to the extruder when it activates an extruder, and during prep, load and unload. With the IFS drive at stock IRUN 9 and IHOLD 0 (coils shorted at standstill), that held the clamped lane back and the extruder slipped: the first Benchy printed nothing. With the drive disabled, E30 and E100 came out fine.

Stock keeps the feed motor off while printing, with the extruder pulling through the clamped lane. So the drive stepper's `sync_to_extruder` in `AFC_IFS` releases the motor instead of syncing it. Feed moves (`lane.move`) still enable the motor as normal. Where stock pushes the lane in step with the extruder (the flush), the unit syncs it explicitly for that move only.

## Lane lengths

- From the inlet stop (filament pushed in until the feed gear) to the toolhead sensor trip is about 640 mm. Measured on lane 1 and lane 2; the stock first-load limit is 650 mm.
- From the point where a hand-pulled tip rests, 188 mm to the toolhead sensor trip was measured with `FORCE_MOVE`.
- A parked lane sits 70 mm back (`dist_hub: 70` per lane, the stock `UnloadIFSSpace`).
- `tool_stn` (sensor to nozzle) is measured at 50 mm: with the nozzle at 220 °C and the lane and extruder pushed together, filament came out between 45 and 55 mm past the toolhead sensor. Stock has no `tool_stn`: after the sensor trip it stops the IFS and flushes with `G1 E90` while the IFS pushes, so it purges 90 mm from the sensor.
- `CALIBRATE_AFC BOWDEN=` does not work as is: for direct lanes it first retracts until the load (silk) sensor clears, and that sensor is at the lane inlet before the feed gear.

## Purge chute

Stock enters and leaves the chute along Y only. AFC's Park, Poop and Brush macros move diagonally in one `G1 X.. Y..` (there is no approach option) and can catch the chute walls. `AFC_IFS` provides `ADX_PARK`, `ADX_POOP` and `ADX_BRUSH`, and at connect it sets AFC's `park_cmd`, `poop_cmd` and `wipe_cmd` to them, but only where `AFC.cfg` still has the AFC defaults. `AFC.cfg` stays upstream.

AFC's order is: unload = cut, park; load = poop, wipe (kick off), wipe. `direct_load` in AFC loads to the nozzle on insert, where stock parks. HTLF assumes home means no lane pressed, while the IFS home is slot 1.

## Unload

Unload follows stock (see [Stock load and unload](stock-firmware.md#stock-load-and-unload)): the lane retracts until the toolhead sensor clears, and the extruder never retries. AFC does the opposite (extruder retries up to `tool_max_unload_attempts`, then a blind lane retract), so `tool_max_unload_attempts` is 0 and the unit replaces the retract.

The reason is that the toolhead sensor sits on the lane side of the cutter, so only the IFS retracting the lane clears it. Pulling the filament out by hand moves the sensor from 0.007 to 0.317.

## Selector

- The unit homes once per startup, tracks the selector position and moves from slot to slot, as stock does (`AFC_HTLF` would re-home after every lane). It re-homes after a homing failure and when a different lane is selected.
- After a move the selector parks at the neutral position (45°), because otherwise lane 1 stays clamped.
- `QUERY_ENDSTOPS` shows `IFS_1_home:TRIGGERED` at home, and `AFC_HOME_UNIT UNIT=IFS_1` works.
- The speed is the stock 70.43°/s with no ramp (`selector_movement_speed: 70.43`, `selector_movement_accel: 0`).

## Open

- The positions in `AFC_Macro_Vars.cfg` (cut, park, purge, kick, brush) were upstream placeholders. The stock AD5X change sequence is in `firmwareExe`, not in `printer.base.cfg`.
