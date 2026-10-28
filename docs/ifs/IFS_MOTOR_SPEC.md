# AD5X IFS motor spec (research, 2026-10-25)

Bottom line: no source found that gives the exact model or electrical ratings of the AD5X IFS motors. Everything electrical below is inferred from the photo (35BYJ46-class) and generic 35BYJ46 listings. Measure the real motor before trusting any number.

## 1. Motor identity

| Fact | Status | Source |
|---|---|---|
| IFS has two separate stepper motors: filament feed (white connector) and channel change/selector (blue connector) | Confirmed | https://filament2print.com/de/flashforge-ad5x-ersatzteile/3902-motoren-flashforge-ad5x.html ; https://partsbuilt.com/ifs-filament-feeding-motor-for-ad5x-flashforge/ ; https://partsbuilt.com/stepper-motor-for-ifs-channel-changing-ad5x-flashforge/ (titles seen in search only, pages returned 403) |
| Motor type = 35 mm can-stack geared PM stepper, blue molded housing, D-flat shaft | Inferred from user photo (capture.png); no source names "35BYJ46" for AD5X |
| Model number | NOT FOUND |
| Rated voltage | NOT FOUND. Generic 35BYJ46 is 12 V typical; variants 5-36 V exist (https://www.micro-steppermotor.com/sale-14494393-35byj46-voltage-pm-stepper-motor-7-5-stepper-motor-5-wire-permanent-magnet-stepper-motor.html ; https://maintexmotors.com/product/35byj46-stepper-motor/ lists 3-24 V) |
| Coil resistance | NOT FOUND. Generic: 130 ohm (12 V) and 300 ohm (12 V/24 V) variants; Maintex range 10-600 ohm |
| Rated phase current | NOT FOUND. A generic 12 V 130 ohm vendor listing says 100 mA/phase |
| Step angle | Inferred: 7.5 deg (rotor) with typical 1/42.5 or 1/85 gearbox -> 3.75 or 15 deg-class output; Maintex lists step angles 3.75/7.5/15 and ratios 1/85, 1/42.5, 1/127. Actual ratio NOT FOUND |
| Wires / connector | NOT FOUND. Photo shows several thin wires out of the blue housing; 35BYJ46 are commonly 5-wire unipolar (center tap) or 4-wire. Connector colours: feed = white, selector = blue (confirmed, filament2print) |
| Shaft | D-flat (from photo) |

Not found anywhere: teardowns, Reddit/Facebook/forum posts, GitHub issues, or AliExpress/Amazon listings naming the AD5X IFS motor model. partsbuilt.com pages blocked fetch (HTTP 403).

## 2. Replacement availability

- filament2print.com (Germany, EU): "Motoren fuer Flashforge AD5X", SKU FLASHFORGE-AD5X-MOTOR-XYAXIS, EUR 15.86 (VAT status ambiguous on page). Variants: X/Y, IFS channel change (blue plug), IFS filament feed (white plug), motor with feed gear. Stock shown 0 at fetch time; est. delivery 5-7 days. Specs not listed. https://filament2print.com/de/flashforge-ad5x-ersatzteile/3902-motoren-flashforge-ad5x.html
- partsbuilt.com: separate listings for IFS filament feeding motor, IFS channel changing stepper, extruder stepper with gear, and whole IFS module. Prices NOT retrieved (403). https://partsbuilt.com/ifs-filament-feeding-motor-for-ad5x-flashforge/ , https://partsbuilt.com/ifs-module-for-ad5x-flashforge/
- Whole IFS parts kit: 123-3D (UK) "IFS Host System Parts" GBP 73.00 inc VAT. https://www.123-3d.co.uk/Flashforge-IFS-Host-System-Parts-for-Flashforge-AD5X-20004652001-i13636.html
- Shipping to US/other not verified for any shop. Generic 35BYJ46 are on Amazon (e.g. https://www.amazon.com/35BYJ46-Permanent-Magnet-Stepper-Repair/dp/B0B3MHJBS2) but connector/resistance must match.

## 3. Safe current (all inferred)

Stepper rms currents with 0.5 ohm sense: irun 9, vsense 0 -> 0.138 A rms; irun 31, vsense 1 -> 0.245 A rms.

- A 35BYJ46-class motor is tiny: 12 V / 130 ohm gives ~92 mA per phase DC; 300 ohm variants ~40-80 mA. Likely rated about 0.08-0.10 A per phase.
- Even stock 0.138 A rms (0.195 A peak) is likely at or above that rating for a 130 ohm motor; 0.245 A rms is ~2.5x a typical rating -> expect heavy heating (can-stack coils of 130-300 ohm dissipate I^2R: 0.245^2 x 130 x 2 phases ~ 15 W worst case, vs ~5 W at 0.138 A; both far above what a 35 mm can sheds, and the blue plastic melts ~100-130 C). That is consistent with the melted housing.
- Conclusion: yes, probably rated below 0.245 A, plausibly below 0.138 A. Do not use irun 31/vsense 1. Measure coil resistance first; if ~130 ohm, target <=0.1 A rms (irun ~6, vsense 0 -> ~0.09 A rms); stealthChop/idle current reduction (ihold low) recommended since feed motor idles most of the time. Temperature rise cannot be quantified from sources (no datasheet); treat as unknown, check by touch after short runs.
- Note a 24 V supply on a 130 ohm motor is fine only because the TMC-type driver chops to current; the DC rating (12 V) is irrelevant to chopper drive, current is the limit.
