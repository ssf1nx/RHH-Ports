# What is this folder?
This is the `buildtools` folder which houses some custom tools used for building open source ports. For example, Super Mario Bros. Remastered at time of writing uses a custom build of `Godot 4.5.1.rc`. Godot 4.5's export templates use a later GLIBC than ArkOS, so custom Linux ARM export templates were built to accommodate.

You should only be wading around in this folder if you're a dev and/or know what you're doing. It isn't something the typical port enjoyer needs.