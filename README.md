# BoostByGear

A [Custom Shaders Patch](https://acstuff.club/patch/) (CSP) Lua app for
Assetto Corsa that lets you cap turbo boost independently per gear —
useful for taming wheelspin off the line in low gears without giving up
top-end power in the higher ones.

## Features

- Independent boost limit (0–100%) for 1st through 5th+ gear, each on its
  own slider
- A master switch that is **remembered**: once BOOST CONTROL is on it stays
  on across sessions and lobbies until you switch it off — no more
  re-enabling it every time you join a server
- A **hotkey**: bind any key or wheel/gamepad button to toggle the limiter,
  even with the window closed; a toast confirms each toggle
- Live readout of target vs. actual boost, normalized against the session's
  observed peak so it reads correctly on cars whose max boost isn't a flat
  1.0 bar
- The status capsule tells you when the current car can't be limited
  (naturally aspirated, or a turbo AC doesn't let apps adjust)
- Turning the switch off always restores full boost, and the app restores
  full boost when the script unloads (session end, CSP reload), so you're
  never left stuck at a clamped value
- Settings auto-save to `config.ini` and reload automatically next session
- "Liquid Glass" glassmorphism UI

## Requirements

- Assetto Corsa
- [Custom Shaders Patch](https://acstuff.club/patch/) (the app uses CSP's
  Lua app APIs, so it won't load without it). The hotkey row needs a build
  with `ac.ControlButton`; on older builds the row just says so and the
  rest of the app works as before.

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
you're currently in.

To bind a hotkey, click the **HOTKEY** capsule at the bottom and press the
key or wheel/gamepad button you want. Hover the capsule and press Delete
to unbind. The binding is stored by CSP in your `controls.ini`.

Your slider values and the state of the switch are saved to `config.ini`
automatically and reloaded the next time the app starts.

### How the switch behaves

- **On stays on.** Leave a session with the switch on and the limiter is
  back on from the first frame of the next one, with a toast reminding you.
  Switch it off (click or hotkey) and it stays off.
- **Closing the window doesn't change anything.** CSP keeps running the app
  while its window is hidden, so the switch — not the window — decides
  whether boost is limited. Use the hotkey or reopen the window to turn it
  off.
- **Unloading restores full boost.** When the script itself unloads
  (leaving the session, a CSP Lua reload) the app sets the wastegate back to
  100% so the car is never left clamped; if the switch was on it re-applies
  the limiter when the next session starts.

### What it can and can't limit

Assetto Corsa only lets apps change the turbo wastegate on cars whose turbo
is cockpit-adjustable — the same cars where the in-game turbo +/- keys do
something. On those cars each gear's target becomes the wastegate setting.
On a car whose turbo isn't adjustable the status capsule shows **TURBO
LOCKED**, and **NO TURBO** on naturally aspirated cars; the app leaves such
cars alone rather than pretending.

## Configuration

`config.ini` is written by the app, but it's plain INI if you want to edit
it by hand (the app must not be running while you do):

| Section / key | Meaning |
|---|---|
| `[BOOST_PER_GEAR] GEAR_1` … `GEAR_5` | Boost target per gear in percent (0–100, snapped to steps of 10). `GEAR_1` also covers neutral and reverse, `GEAR_5` covers 5th and every gear above. |
| `[SETTINGS] ACTIVE` | `1` if the master switch is on, `0` if off. |

The hotkey binding lives in `controls.ini` under
`[BoostByGear/Toggle boost control]` and is managed by CSP.

## License

Code is [MIT licensed](LICENSE). See [`fonts/README.md`](fonts/README.md)
for the fonts' separate licenses.
