# The Simpons: Hit and Run

## Where did this come from?
The `hitandrun` binary itself comes from [R36SWiki](https://r36swiki.com/wiki-simpsonshnr.html) and it was apparently compiled by or for them. The launchscript has been cleaned up, a gptk file added, and proper assets checking.

The origin of this compilation is either https://github.com/ZenoArrows/The-Simpsons-Hit-and-Run or a fork of it, due to familiar filepaths being present in the binary.

```
strings hitandrun | grep "/target/code/mission/missionstage.cpp"
strings hitandrun | grep "/target/libs/scrooby/src/utility/EnumConversion.cpp"
strings hitandrun | grep "r36swiki.com"
```

## Installation
You need the original Windows PC version of The Simpsons: Hit and Run to use this port. Copy the following items from your installation to `simpsons_h&r/gamedata`:

Directories:
- art
- movies
- scripts
- sound

Files:
- ambience.rcf
- carsound.rcf
- dialog.rcf
- music00.rcf
- music01.rcf
- music02.rcf
- music03.rcf
- nis.rcf
- scripts.rcf
- sound.fx.rcf

You will also need to source the original `hitandrun` binary from the R36SWiki link above. Download `hitandrun.zip`, grab the `hitandrun` binary file from within, and copy it to `simpsons_h&r`. This is necessary until reproducible build steps from a public repository are discovered.