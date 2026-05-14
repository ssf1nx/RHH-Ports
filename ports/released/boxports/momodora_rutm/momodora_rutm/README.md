## Installation
Download the linux version and add game files to `momodora_rutm/gamedata`.

## Default Gameplay Controls
| Button            | Action |
|--                 |--|
| START             | Menu |
| D-PAD / JOYSTICK  | Move |
| A                 | Jump |
| B                 | Melee Attack |
| X                 | Roll |
| Y                 | Item |
| L1                | Switch Item |
| R1                | Ranged Attack |
| L2 (Held)         | Map |

## Notes
For the time being this port requires a decent cpu (`power`) due to short-lived frame drops when particle effects appear on screen. This will be fine in early gameplay, but later boss fights will be more prolonged.

Native gamepad is nonfunctional. GPToKeyB is used to map keyboard inputs and the provided `config.ini` is set to show gamepad glyphs. If the glyphs ingame are incorrect, please reassign buttons in `momodora.gptk` as you see fit.

## Runtimes

This port requires the following runtimes in `PortMaster/libs`:

- **Westonpack** — [weston_pkg_0.2.squashfs](https://github.com/JeodC/RHH-Ports/raw/main/runtimes/weston_pkg_0.2.squashfs)

[Pharos](https://github.com/JeodC/RHH-Ports/releases/download/ports-latest/pharos.zip) will fetch these automatically when installing the port. Otherwise download them manually from the [runtimes folder](https://github.com/JeodC/RHH-Ports/tree/main/runtimes) and drop them in `PortMaster/libs`.

## Thanks
bombservice -- The game  
JohnnyOnFlame -- Initial port work 