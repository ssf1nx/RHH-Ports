## Installation
Buy the game and copy all data to `grappledog/assets`.

## Patching on a PC (optional, faster)
Patching on weaker devices can take up to an hour. If you'd rather not wait for on-device patching, you can patch from your PC (takes 5-10 minutes) by following the steps below:

- Open a terminal in your Steam install directory (e.g. `Z:\SteamLibrary\steamapps\common\Grapple Dog`).
- Download the decode tool and run it:
   ```bash
   curl -L -o gmtoolkit.exe https://github.com/JeodC/RHH-Ports/raw/main/ports/released/gamemakerengine/grappledog/grappledog/tools/gmtoolkit.exe
   gmtoolkit.exe data.win textures --repack --page-size 1024 --block 6x6 --quality -fastest --set-flags Fullscreen --clear-flags Scale
   ```
   `--block 6x6 --quality -fastest` matches the on-device 480p preset (smaller runtime footprint, slightly lower visual quality). Bump to `--block 5x5 --quality -fast` or `--block 4x4 --quality -medium` for sharper textures if your device has the RAM.
- Verify you have a new `textures/` folder. Copy the install directory's contents including that folder into `grappledog/assets/` on the device.
- Launch the port. The launcher sees `textures/` in `assets/` and skips the steps you already did.

Linux / macOS users can build `gmtoolkit` from source in [buildtools/gmtoolkit/](https://github.com/JeodC/RHH-Ports/tree/main/buildtools/gmtoolkit) (`cmake -B build && cmake --build build`).

## Notes
Grapple Dog is a heavy game with both cpu and memory. Patching aims to remove the memory bottlenecks, and the launchscript `Grapple Dog.sh` has a tweakable cpu cap. This port was tested on the following devices:

- AYN Thor (full speed)
- RG353V (some slowdowns)
- TrimUI Smart Pro (some slowdowns)

In all cases the first few levels were completable.

## Thanks
Medallion Games -- The amazing game.  
JohnnyOnFlame -- GMLoader-Next, FMOD compatibility, and [UTMT-CLI fork](https://github.com/JohnnyonFlame/UTMT-PortMaster).  
Jeod -- GMLoader-Next improvements and Game Port.  
UnderminersTeam -- For the original [UTMT-CLI utility](https://github.com/UnderminersTeam/UndertaleModTool).  
