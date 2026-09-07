# BoostByGear

A [Custom Shaders Patch](https://acstuff.club/patch/) (CSP) Lua app for
Assetto Corsa that lets you cap turbo boost independently per gear —
useful for taming wheelspin off the line in low gears without giving up
top-end power in the higher ones.

## Features

- Independent boost limit (0–100%) for 1st through 5th+ gear, each on its
  own slider
- Live readout of target vs. actual boost, normalized against the session's
  observed peak so it reads correctly on cars whose max boost isn't a flat
  1.0 bar
- One master on/off switch — turning it off (or closing the app mid-session)
  always restores full boost, so you're never left stuck at a clamped value
- Settings auto-save to `config.ini` and reload automatically next session
- Works with both wastegate-adjustable and generic turbo setups
- "Liquid Glass" glassmorphism UI

## Requirements

- Assetto Corsa
- [Custom Shaders Patch](https://acstuff.club/patch/) (the app uses CSP's
  Lua app APIs, so it won't load without it)

## Installation

1. Copy this folder into your Assetto Corsa apps directory so the path looks
   like:
   ```
   Documents/Assetto Corsa/apps/lua/BoostByGear/BoostByGear.lua
   Documents/Assetto Corsa/apps/lua/BoostByGear/manifest.ini
   Documents/Assetto Corsa/apps/lua/BoostByGear/config.ini
   Documents/Assetto Corsa/apps/lua/BoostByGear/icon.png
   Documents/Assetto Corsa/apps/lua/BoostByGear/fonts/...
   ```
2. Launch Assetto Corsa, open the CSP app list, and enable **BoostByGear**.

## Usage

Flip the **BOOST CONTROL** switch on, then set each gear's target with its
slider. The gauge shows your target line and the car's actual boost in
real time; the per-gear mini bars along the top highlight whichever gear
you're currently in. Turn the switch off (or just close the app) to
instantly return to full boost.

Your slider values are saved to `config.ini` automatically and reloaded the
next time you open the app.

## License

Code is [MIT licensed](LICENSE). See [`fonts/README.md`](fonts/README.md)
for the fonts' separate licenses.
