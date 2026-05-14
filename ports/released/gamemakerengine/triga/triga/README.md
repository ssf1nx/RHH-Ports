## Installation
Copy your Triga game files to `triga/assets`. If using Steam data, the game will be patched to stretch to fit.

## Default Gameplay Controls
| Button            | Action |
|--                 |--|
| SELECT            | Quit to menu |
| D-PAD / JOYSTICK  | Move cursor |
| A                 | Select / place piece |
| R1                | Reset level |
| L1                | Undo |

## Runtimes

This port requires the following runtimes in `PortMaster/libs`:

- **.NET 8** — [dotnet-8.0.12.squashfs](https://github.com/JeodC/RHH-Ports/raw/main/runtimes/dotnet-8.0.12.squashfs)
- **GMToolkit** — [gmtoolkit.squashfs](https://github.com/JeodC/RHH-Ports/raw/main/runtimes/gmtoolkit.squashfs)
- **GMLoader-Next** — [gmloadernext.squashfs](https://github.com/JeodC/RHH-Ports/raw/main/runtimes/gmloadernext.squashfs)

[Pharos](https://github.com/JeodC/RHH-Ports/releases/download/ports-latest/pharos.zip) will fetch these automatically when installing the port. Otherwise download them manually from the [runtimes folder](https://github.com/JeodC/RHH-Ports/tree/main/runtimes) and drop them in `PortMaster/libs`.

## Thanks
Cicada Games -- The game!  
JohnnyOnFlame -- GMLoader-Next  
Cyril Deletre -- GMTools audio compressor  