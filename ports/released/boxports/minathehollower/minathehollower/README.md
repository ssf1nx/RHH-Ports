## Installation
Add your game assets to `minathehollower/data`. If you have a GOG installer .sh file, copy it to `minathehollower/data` and a first-run will unpack the assets for you.

If using Steam, you can get the Linux version from https://steamdb.info/app/1875580/depots/ where you will need to download two:

- https://steamdb.info/depot/1875581 (this is also on Windows, the data/*.pak files)
- https://steamdb.info/depot/1875583/ (the Linux launcher and specific Linux files)

*Note: If using Steam, you may encounter an issue with `libsteam.so`. A future update from YCG should rectify the issue.

## Requirements
Mina the Hollower is a **Vulkan-only** game. Your device needs a working Vulkan driver and a native X11/Xwayland display.

## Thanks
- **Yacht Club Games** — for *Mina the Hollower* itself  
- **ptitSeb** — [Box64](https://github.com/ptitSeb/box64)  
- **Gabriel Huber (Yepoleb)** — [gogextract](https://github.com/Yepoleb/gogextract), used to unpack the GOG/Humble installer on-device.  
