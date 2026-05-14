## Installation
Copy game data to `ooo/assets`.

## Notes
Needs instance culling due to 10560×8160 room, perform in `gml_GlobalScript_scCameraGameplay`

## Runtimes

This port requires the following runtimes in `PortMaster/libs`:

- **.NET 8** — [dotnet-8.0.12.squashfs](https://github.com/JeodC/RHH-Ports/raw/main/runtimes/dotnet-8.0.12.squashfs)
- **GMToolkit** — [gmtoolkit.squashfs](https://github.com/JeodC/RHH-Ports/raw/main/runtimes/gmtoolkit.squashfs)
- **GMLoader-Next** — [gmloadernext.squashfs](https://github.com/JeodC/RHH-Ports/raw/main/runtimes/gmloadernext.squashfs)

[Pharos](https://github.com/JeodC/RHH-Ports/releases/download/ports-latest/pharos.zip) will fetch these automatically when installing the port. Otherwise download them manually from the [runtimes folder](https://github.com/JeodC/RHH-Ports/tree/main/runtimes) and drop them in `PortMaster/libs`.

## Thanks

JohnnyOnFlame -- GMLoader-Next  