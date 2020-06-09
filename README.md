# FntEdit

This is a small program I cobbled together to help with making edits to the .fnt files
in Puyo Puyo 20th Anniversary for the Nintendo DS, while helping with the English
[fan translation](https://www.romhacking.net/translations/4522/)

### Building

To compile the application, you will need:
* [Nim](https://nim-lang.org/)
* [SDL2](https://www.libsdl.org/)
* [SDL2_gfx](https://www.ferzkopp.net/wordpress/2016/01/02/sdl_gfx-sdl2_gfx/)
* [iup](https://www.tecgraf.puc-rio.br/iup/)

```
nimble install       # get the dependencies
nim c fntedit.nim    # compile
```
