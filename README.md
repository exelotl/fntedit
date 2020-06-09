# FntEdit

This is a small program I cobbled together to help with editing the .fnt files
used by Puyo Puyo 20th Anniversary for the Nintendo DS, while helping with the [English
translation](https://www.romhacking.net/translations/4522/) by Precise Museum.

![image](https://user-images.githubusercontent.com/569607/84211929-714e1800-aab4-11ea-9280-efc193a4c411.png)

### Building

To compile the application, you will need:
* [Nim](https://nim-lang.org/)
* [SDL2](https://www.libsdl.org/)
* [SDL2_gfx](https://www.ferzkopp.net/wordpress/2016/01/02/sdl_gfx-sdl2_gfx/)
* [iup](https://www.tecgraf.puc-rio.br/iup/)

Once everything is installed, clone the repo and compile like so:
```
nimble install          # get the dependencies
nim c -r fntedit.nim    # compile and run!
```
