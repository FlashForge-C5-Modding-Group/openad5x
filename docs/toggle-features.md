# How to toggle features

A few OpenAD5X features are switches you can turn on or off.

## Ways to change a switch

=== "Fluidd"

    Open the dashboard. **Adaptive_Mesh** is on the **Fans & Outputs** card, and **end_unload**
    is in the filament sensors list.

=== "Mainsail"

    **Adaptive_Mesh** is on the dashboard under **Miscellaneous**, and **end_unload** with the
    filament sensors.

=== "Console"

    ```
    SET_PIN PIN=Adaptive_Mesh VALUE=0
    SET_FILAMENT_SENSOR SENSOR=end_unload ENABLE=0
    ```

## Switches

| Switch | Default | What it does |
| --- | --- | --- |
| **Adaptive_Mesh** | On | On: `START_PRINT` probes the mesh only where the print is. Off: the full bed. |
| **end_unload** | On | Unloads the filament at the end or cancel of a print. The setting survives restarts. |
