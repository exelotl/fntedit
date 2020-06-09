import sdl2/[sdl, sdl_gfx_primitives]
import lz11
import trick
import os, strformat, strutils, streams, parseopt, parseutils
import unicode, math
from iup import nil

const ScreenW = 640
const ScreenH = 480

discard iup.open(nil, nil)

if sdl.init(INIT_VIDEO) != 0:
  sdl.logCritical(LOG_CATEGORY_ERROR, "Can't initialize SDL: %s", sdl.getError())
  quit(0)
  
var window = sdl.createWindow(
  title = "FntEdit",
  x = WINDOWPOS_UNDEFINED,
  y = WINDOWPOS_UNDEFINED,
  w = ScreenW,
  h = ScreenH,
  flags = 0
)

var renderer = sdl.createRenderer(
  window,
  index = -1,
  flags = RENDERER_SOFTWARE
)


# Set up a shared palette for all the glyphs and UI?
var colors = [
  Color(r: 0, g: 0, b: 0, a:0),
  Color(r: 255, g: 255, b: 255, a:255),
  Color(r: 140, g: 140, b: 140, a:255),
  Color(r: 100, g: 100, b: 100, a:255),
  Color(r: 60, g: 60, b: 60, a:255),
  Color(r: 30, g: 30, b: 30, a:255),
]
var pal = allocPalette(colors.len)
discard setPaletteColors(pal, addr colors[0], 0, colors.len)


proc plot(s:Surface, x,y:int, index:uint8) =
  ## Set a pixel on an 8bpp paletted surface  
  let pixels = cast[ptr UncheckedArray[uint8]](s.pixels)
  if x < 0 or y < 0 or x >= s.w or y >= s.h:
    return
  pixels[x + y*s.w] = index

proc getPixel(s:Surface, x,y:int): uint8 =
  let pixels = cast[ptr UncheckedArray[uint8]](s.pixels)
  if x < 0 or y < 0 or x >= s.w or y >= s.h:
    return 0
  return pixels[x + y*s.w]
  
proc getU8At(data:var string, byteOffset:int):uint8 =
  data[byteOffset].uint8

proc getU16At(data:var string, byteOffset:int):uint16 =
  cast[ptr uint16](addr data[byteOffset])[].uint16

proc getU32At(data:var string, byteOffset:int):uint32 =
  cast[ptr uint32](addr data[byteOffset])[].uint32

proc setU8At(data:var string, byteOffset:int, v:uint8) =
  cast[ptr uint8](addr data[byteOffset])[] = v

proc setU16At(data:var string, byteOffset:int, v:uint16) =
  cast[ptr uint16](addr data[byteOffset])[] = v

proc setU32At(data:var string, byteOffset:int, v:uint32) =
  cast[ptr uint32](addr data[byteOffset])[] = v

type FntInfo = object
  glyphWidth*: int
  glyphHeight*: int
  isComp: bool

type FntGlyph = object
  rune*: Rune
  span*: int
  surface*: Surface
  texture*: Texture

proc initGlyph(rune:Rune, fnt:FntInfo, span:int): FntGlyph =
  result.rune = rune
  result.span = span
  result.surface = createRGBSurface(0, fnt.glyphWidth, fnt.glyphHeight, 8, 0,0,0,0)
  discard setSurfacePalette(result.surface, pal)
  # result.texture = createTextureFromSurface(renderer, g.surface)
  result.texture = createTexture(renderer, PIXELFORMAT_RGBA8888, TEXTUREACCESS_STATIC, fnt.glyphWidth, fnt.glyphHeight)
  discard setTextureBlendMode(result.texture, BLENDMODE_BLEND)

proc updateTexture(g: var FntGlyph) =
  var fmt: uint32
  discard queryTexture(g.texture, addr fmt, nil, nil, nil)
  let pixelFormat = allocFormat(fmt)
  let textureSurface = convertSurface(g.surface, pixelFormat, 0)
  discard updateTexture(g.texture, nil, textureSurface.pixels, textureSurface.pitch)
  freeSurface(textureSurface)
  freeFormat(pixelFormat)

var glyphs: seq[FntGlyph]
var fntInfo: FntInfo
var fntData: string

let sidebarScale = 2
let sidebarGlyphsWide = 8
var sidebarGlyphsTall = 0
var sidebarRect = Rect(x: 2, y: 8, w: 0, h: 0)

let canvasScale = 12
var canvasRect = Rect(x: 300, y: 20, w: 0, h: 0)

var currentGlyphIndex = 0


proc draw()  ## Refresh the screen after something changed


proc loadFont(filePath:string) =
  
  currentGlyphIndex = 0
  glyphs = @[]
  fntInfo = FntInfo()
  
  fntData = readFile(filePath)
  
  if fntData.startsWith("COMP"):
    let decompIn = newStringStream(fntData)
    let decompOut = newStringStream("")
    decompress(decompIn, fntData.len, decompOut)
    fntData = decompOut.data
    fntInfo.isComp = true
  
  let numGlyphs = fntData.getU32At(0x0000000C).int
  fntInfo.glyphWidth = fntData.getU32At(0x00000008).int
  fntInfo.glyphHeight = fntData.getU32At(0x00000004).int
  
  canvasRect.w = fntInfo.glyphWidth * canvasScale
  canvasRect.h = fntInfo.glyphHeight * canvasScale
  
  sidebarGlyphsTall = ceil(numGlyphs / sidebarGlyphsWide).int
  sidebarRect.w = sidebarGlyphsWide * fntInfo.glyphWidth * sidebarScale
  sidebarRect.h = sidebarGlyphsWide * fntInfo.glyphHeight * canvasScale
  
  let pitch = fntInfo.glyphWidth div 2
  
  var i = 0x00000030
  for n in 0..<numGlyphs:
    var rune = fntData.getU16At(i).Rune   ## which unicode character is this glyph
    i += 2
    var span = fntData.getU16At(i).int    ## how much horizontal space does this glyph take up?
    i += 2
    
    var glyphStart = i
    var glyph = initGlyph(rune, fntInfo, span)
    # echo fmt"rune:{rune}, span:{span}"
    
    for y in 0..<fntInfo.glyphHeight:
      for x in 0..<pitch:
        let p = fntData.getU8At(glyphStart + x + y*pitch)
        let a = (p and 0b00001111) shr 0
        let b = (p and 0b11110000) shr 4
        glyph.surface.plot(x*2 + 0, y, a.uint8)
        glyph.surface.plot(x*2 + 1, y, b.uint8)
    
    glyph.updateTexture()
    glyphs.add(glyph)
    
    # advance to the next glyph in the fnt data
    i += pitch * fntInfo.glyphHeight
  draw()

proc saveFont(filePath:string) =
  var outData = fntData[0..<0x00000030]  # copy existing data
  outData.setU8At(0x0000000C, glyphs.len.uint8)
  outData.setU32At(0x00000008, fntInfo.glyphWidth.uint32)
  outData.setU32At(0x00000004, fntInfo.glyphHeight.uint32)
  var outStream = newStringStream(outData)
  outStream.setPosition(outData.len)
  
  let pitch = fntInfo.glyphWidth div 2
  for glyph in glyphs:
    outStream.write(glyph.rune.uint16)
    outStream.write(glyph.span.uint16)
    for y in 0..<fntInfo.glyphHeight:
      for x in 0..<pitch:
        let a = glyph.surface.getPixel(x*2 + 0, y)
        let b = glyph.surface.getPixel(x*2 + 1, y)
        let p = uint8(((a shl 0) and 0b00001111) or ((b shl 4) and 0b11110000))
        outStream.write(cast[char](p))
  
  outData = outStream.data
  
  if fntInfo.isComp:
    let compIn = newStringStream(outData)
    let compOut = newStringStream("")
    compress(compIn, outData.len, compOut, comp=true)
    outData = compOut.data
  
  writeFile(filePath, outData)
  

proc draw() =
  discard setRenderDrawColor(renderer, 0, 0, 0, 255)
  discard renderClear(renderer)
  
  # sidebar
  for i, glyph in glyphs:
    let x = (i mod sidebarGlyphsWide) * fntInfo.glyphWidth
    let y = (i div sidebarGlyphsWide) * fntInfo.glyphHeight
    var dstRect = Rect(
      x: sidebarRect.x + x * sidebarScale,
      y: sidebarRect.y + y * sidebarScale,
      w: glyph.surface.w * sidebarScale,
      h: glyph.surface.h * sidebarScale,
    )
    
    if currentGlyphIndex == i:
      discard setRenderDrawColor(renderer, 0, 100, 200, 255)
      discard renderFillRect(renderer, addr dstRect)
    
    discard renderCopy(renderer, glyph.texture, nil, addr dstRect)
  
  # canvas
  let canvasGlyph = glyphs[currentGlyphIndex]
  discard setRenderDrawColor(renderer, 0, 100, 200, 255)
  discard renderFillRect(renderer, addr canvasRect)
  var spanRect = canvasRect
  spanRect.w = canvasGlyph.span * canvasScale
  discard setRenderDrawColor(renderer, 200, 100, 0, 255)
  discard renderFillRect(renderer, addr spanRect)
  discard renderCopy(renderer, canvasGlyph.texture, nil, addr canvasRect)
  discard stringColor(renderer, int16(canvasRect.x), int16(canvasRect.y + canvasRect.h + 2), fmt"{canvasGlyph.rune.int32:04X}", 0xffffffff'u32)
  renderPresent(renderer)


proc sidebarClicked(mousePos:Point) =
  let gx = (mousePos.x - sidebarRect.x) div (fntInfo.glyphWidth * sidebarScale)
  let gy = (mousePos.y - sidebarRect.y) div (fntInfo.glyphHeight * sidebarScale)
  var gi = gx + gy*sidebarGlyphsWide
  currentGlyphIndex = gi.clamp(0, glyphs.len-1)
  draw()

proc canvasSet(mousePos:Point, color:uint8) =
  let x = (mousePos.x - canvasRect.x) div (canvasScale)
  let y = (mousePos.y - canvasRect.y) div (canvasScale)
  var g = glyphs[currentGlyphIndex]
  # echo fmt"plot: {x}, {y}, {color.int}"
  g.surface.plot(x, y, color)
  g.updateTexture()
  draw()


const help = """
FONT EDITOR
-----------

Open a file to get started!

KEYS
----
F1 :: show this help

O  :: open .fnt file
S  :: save .fnt file

INS  :: insert copy of current glyph
DEL  :: delete current glyph

Space :: Change unicode value of current glyph

]  :: increase width of current glyph
[  :: decrease width of current glyph

,  :: swap places left
.  :: swap places right

GLYPH PICKER
------------
Left mouse :: set current glyph

CANVAS
------
Left mouse  :: draw
Right mouse :: erase
""".split('\n')

proc drawHelp() =
  discard setRenderDrawColor(renderer, 0, 0, 0, 255)
  discard renderClear(renderer)
  for i, str in help:
    discard stringColor(renderer, 20, i.int16 * 10 + 20, str, 0xffffffff.uint32)
  renderPresent(renderer)
  
drawHelp()

# loadFont("en/font_en.fnt")
# draw()

proc fntFileOpenDialog() =
  var dialog = iup.fileDlg()
  iup.setAttribute(dialog, "DIALOGTYPE", "OPEN")
  iup.setAttribute(dialog, "TITLE", "Select a .fnt file to edit")
  iup.setAttribute(dialog, "FILTER", "*.fnt")
  iup.popup(dialog, iup.IUP_CURRENT, iup.IUP_CURRENT)
  let res = iup.getInt(dialog, "STATUS")
  if res != -1:
    let path = $iup.getAttribute(dialog, "VALUE")
    echo path
    loadFont(path) ## currently it's not safe to continue executing if loading messed up :\
    # try:
    #   loadFont(path)
    # except:
    #   discard iup.alarm("Error", getCurrentExceptionMsg(), "OK", nil, nil)
  iup.destroy(dialog)
  
proc fntFileSaveDialog() =
  var dialog = iup.fileDlg()
  iup.setAttribute(dialog, "DIALOGTYPE", "SAVE")
  iup.setAttribute(dialog, "TITLE", "Save .fnt file")
  iup.setAttribute(dialog, "FILTER", "*.fnt")
  iup.popup(dialog, iup.IUP_CURRENT, iup.IUP_CURRENT)
  let res = iup.getInt(dialog, "STATUS")
  if res != -1:
    let path = $iup.getAttribute(dialog, "VALUE")
    echo path
    try:
      saveFont(path)
    except:
      discard iup.alarm("Error", getCurrentExceptionMsg(), "OK", nil, nil)
  iup.destroy(dialog)

proc incSpan() =
  var g = addr glyphs[currentGlyphIndex]
  g.span = (g.span+1).clamp(0, g.surface.w)
  draw()

proc decSpan() =
  var g = addr glyphs[currentGlyphIndex]
  g.span = (g.span-1).clamp(0, g.surface.w)
  draw()


proc insertGlyph() =
  let current = glyphs[currentGlyphIndex]
  var g = initGlyph(current.rune, fntInfo, current.span)
  discard blitSurface(current.surface, nil, g.surface, nil)
  g.updateTexture()
  glyphs.insert(g, currentGlyphIndex)
  inc currentGlyphIndex
  draw()
  
proc deleteGlyph() =
  if glyphs.len > 1:
    glyphs.delete(currentGlyphIndex)
    if currentGlyphIndex >= glyphs.len:
      dec currentGlyphIndex
    draw()
  
proc swapLeft () =
  let i = currentGlyphIndex
  if i > 0:
    (glyphs[i-1], glyphs[i]) = (glyphs[i], glyphs[i-1])
    dec currentGlyphIndex
    draw()
    
proc swapRight () =
  let i = currentGlyphIndex
  if i < glyphs.len-1:
    (glyphs[i+1], glyphs[i]) = (glyphs[i], glyphs[i+1])
    inc currentGlyphIndex
    draw()

var leftMousePressed = false
var rightMousePressed = false
var mousePos: Point

proc tryDraw() =
  # plot a pixel in the currently selected glyph
  if pointInRect(mousePos, canvasRect):
    if leftMousePressed: canvasSet(mousePos, 1)
    elif rightMousePressed: canvasSet(mousePos, 0)


proc inputRune() =
  var g = addr glyphs[currentGlyphIndex]
  var codePoint = fmt"{g.rune.int32:04X}"
  let res = iup.scanf("Enter unicode value:\nCodepoint:%4.4%s\n", addr codePoint[0])
  if res == 1:
    try:
      g.rune = parseHexInt(codePoint).Rune
      draw()
    except:
      discard iup.alarm("Error", getCurrentExceptionMsg(), "OK", nil, nil)

var done = false

while not done:
  var e: sdl.Event

  while sdl.pollEvent(addr(e)) != 0:
    try:
      case e.kind
      of MOUSEBUTTONDOWN:
        let btn = e.button.button
        if btn == BUTTON_LEFT: leftMousePressed = true
        elif btn == BUTTON_RIGHT: rightMousePressed = true
        mousePos = Point(x: e.button.x, y: e.button.y)
        tryDraw()
        
        if pointInRect(mousePos, sidebarRect):
          if btn == BUTTON_LEFT:
            sidebarClicked(mousePos)
      
      of MOUSEBUTTONUP:
        let btn = e.button.button
        if btn == BUTTON_LEFT: leftMousePressed = false
        elif btn == BUTTON_RIGHT: rightMousePressed = false
        mousePos = Point(x: e.button.x, y: e.button.y)
        tryDraw()
      
      of MOUSEMOTION:
        mousePos = Point(x: e.button.x, y: e.button.y)
        tryDraw()
      
      of KEYDOWN:
        let sym = e.key.keysym.sym
        case sym:
        of K_o: fntFileOpenDialog()
        of K_s: fntFileSaveDialog()
        of K_INSERT: insertGlyph()
        of K_DELETE: deleteGlyph()
        of K_RIGHTBRACKET: incSpan()
        of K_LEFTBRACKET: decSpan()
        of K_COMMA: swapLeft()
        of K_PERIOD: swapRight()
        of K_SPACE: inputRune()
        of K_F1: drawHelp()
        of K_ESCAPE:
          done = true
          break
        else:
          discard
      of QUIT:
        done = true
        break
      else:
        discard
    except:
      discard iup.alarm("Fatal Error",
        getCurrentExceptionMsg() & "\n\n" &
        getCurrentException().getStackTrace() & "\n\n" &
        "The program will now close. :(",
      "OK", nil, nil)
      done = true
      break
      
  sleep(50)


sdl.destroyRenderer(renderer)
sdl.destroyWindow(window)
sdl.quit()

iup.close()
