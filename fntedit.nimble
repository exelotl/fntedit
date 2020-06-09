# Package

version       = "0.1.0"
author        = "exelotl"
description   = "An editor for the .fnt file format used in the NDS Puyo Puyo games"
license       = "zlib"
srcDir        = ""
bin           = @["fntedit"]


# Dependencies

requires "nim >= 1.2.0"
requires "iup >= 3.0.0"
requires "trick >= 0.1.0"
requires "sdl2_nim >= 2.0.12.0"
