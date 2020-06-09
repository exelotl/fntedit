# lz11 compression/decompression code ported from https://github.com/nickworonekin/puyotools

import streams, os

proc decompress*(src:Stream, srcLen:int, dest:Stream)
proc compress*(src:Stream, srcLen:int, dest:Stream, comp:bool=true)

proc decompress*(inFile, outFile:File) =
  let srcLen = getFileSize(inFile).int
  let src = newFileStream(inFile)
  let dest = newFileStream(outFile)
  decompress(src, srcLen, dest)

proc decompress*(inFile, outFile:string) =
  let src = open(inFile, fmRead)
  defer: close(src)
  let dest = open(outFile, fmWrite)
  defer: close(dest)
  decompress(src, dest)
  
proc compress*(inFile, outFile:File, comp:bool=true) =
  let srcLen = getFileSize(inFile).int
  let src = newFileStream(inFile)
  let dest = newFileStream(outFile)
  compress(src, srcLen, dest, comp)

proc compress*(inFile, outFile:string, comp:bool=true) =
  let src = open(inFile, fmRead)
  defer: close(src)
  let dest = open(outFile, fmWrite)
  defer: close(dest)
  compress(src, dest, comp)

proc decompressToString*(inFile:string):string =
  let inLen = getFileSize(inFile).int
  let inStream = newFileStream(inFile, fmRead)
  defer: inStream.close()
  let outStream = newStringStream("")
  defer: outStream.close()
  decompress(inStream, inLen, outStream)
  return outStream.data

proc `>>`[T](a,b:T):T = a shr b
proc `<<`[T](a,b:T):T = a shl b

proc decompress*(src:Stream, srcLen:int, dest:Stream) =
  var srcPtr = 0x0
  var destPtr = 0x0
  
  # handle COMP compression which is actually just LZ11 with "COMP" at the start
  if src.peekStr(4) == "COMP":
    discard src.readStr(4)
    srcPtr += 4
  
  var destLen = src.readInt32() >> 8
  srcPtr += 4
  if destLen == 0:
    destLen = src.readInt32()
    srcPtr += 4
  
  var buffer: array[0x1000, byte]
  var bufferPtr = 0x0
  
  while srcPtr < srcLen:
    var flag = src.readUint8()
    srcPtr += 1
    
    for i in 0..<8:
      
      if (flag and 0x80) == 0:
        # not compressed
        let val = src.readUint8()
        srcPtr += 1
        dest.write(val)
        destPtr += 1
        buffer[bufferPtr] = val
        bufferPtr = (bufferPtr + 1) and 0xfff
      else:
        # compressed
        var matchDistance, matchLen: int
        let b1 = src.readUint8().int
        let b2 = src.readUint8().int
        srcPtr += 2
        
        case b1 >> 4:
          of 0:
            # 3 bytes
            let b3 = src.readUint8().int
            srcPtr += 1
            matchDistance = (((b2 and 0xf) << 8) or b3) + 1
            matchLen = (((b1 and 0xf) << 4) or (b2 >> 4)) + 17
          of 1:
            # 4 bytes
            let b3 = src.readUint8().int
            let b4 = src.readUint8().int
            srcPtr += 2
            matchDistance = (((b3 and 0xf) << 8) or b4) + 1
            matchLen = (((b1 and 0xf) << 12) or (b2 << 4) or (b3 >> 4)) + 273
          else:
            # 2 bytes
            matchDistance = (((b1 and 0xf) << 8) or b2) + 1
            matchLen = (b1 >> 4) + 1
        
        for j in 0..<matchLen:
          let val = buffer[(bufferPtr - matchDistance) and 0xfff]
          dest.write(val)
          destPtr += 1
          buffer[bufferPtr] = val
          bufferPtr = (bufferPtr + 1) and 0xfff
    
      if srcPtr >= srcLen:
        # we reached the end of the source
        break
      
      if destPtr > destLen:
        raise newException(Exception, "Too much data written to the destination")
      
      flag = flag << 1


# sliding window dictionary used for compression

type LzWindowDictionary = ref object
  windowSize: int
  windowStart: int
  windowLength: int
  minMatchAmount: int
  maxMatchAmount: int
  blockSize: int
  offsetList: seq[seq[int]]

proc newLzWindowDictionary():LzWindowDictionary =
  return LzWindowDictionary(
    windowSize: 0x1000,
    windowStart: 0,
    windowLength: 0,
    minMatchAmount: 3,
    maxMatchAmount: 18,
    blockSize: 0,
    offsetList: newSeq[seq[int]](256)
  )

proc removeOldEntries(dict:LzWindowDictionary, index:int) =
  var i = 0
  while i < dict.offsetList[index].len:
    if dict.offsetList[index][i] >= dict.windowStart:
      break
    else:
      dict.offsetList[index].delete(0)
  # while dict.offsetList[index].len != 0:
  #   if dict.offsetList[index][0] >= dict.windowStart:
  #     dict.offsetList[index].delete(0)

proc search(dict:LzWindowDictionary, decompressedData:string, offset, length:int): seq[int] =
  dict.removeOldEntries(decompressedData[offset].int)
  
  # can't find matches if there isn't enough data
  if offset < dict.minMatchAmount or length - offset < dict.minMatchAmount:
    return @[0, 0]
  
  var match = @[0, 0]
  var matchStart, matchSize: int

  let index = decompressedData[offset].int
  
  for i in countdown(dict.offsetList[index].len-1, 0):
    
    matchStart = dict.offsetList[index][i]
    matchSize = 1
    
    while matchSize < dict.maxMatchAmount and
      matchSize < dict.windowLength and
      matchStart + matchSize < offset and
      offset + matchSize < length and
      decompressedData[offset + matchSize] == decompressedData[matchStart + matchSize]:
        matchSize += 1
    
    if matchSize >= dict.minMatchAmount and matchSize > match[1]:
      # this is a good match
      match = @[offset-matchStart, matchSize]
      if matchSize == dict.maxMatchAmount:
        # don't look for more matches
        break
  
  return match

{.this:dict.}
proc slideWindow(dict:LzWindowDictionary, amount:int) =
  if windowLength == windowSize:
    windowStart += amount
  elif windowLength + amount <= windowSize:
    windowLength += amount
  else:
    windowStart += amount - (windowSize - windowLength)
    windowLength = windowSize

proc slideBlock(dict:LzWindowDictionary) =
  dict.windowStart += dict.blockSize

proc setBlockSize(dict:LzWindowDictionary, size:int) =
  dict.blockSize = size
  dict.windowLength = size

proc addEntry(dict:LzWindowDictionary, decompressedData:string, offset:int) =
  let index = decompressedData[offset].int
  dict.offsetList[index].add(offset)

proc addEntryRange(dict:LzWindowDictionary, decompressedData:string, offset, length:int) =
  for i in 0..<length:
    dict.addEntry(decompressedData, offset + i)


proc compress(src:Stream, srcLen:int, dest:Stream, comp:bool=true) =
  
  var srcString = src.readAll()
  
  var srcPtr = 0x0
  var destPtr = 0x4
  
  var dict = newLzWindowDictionary()
  dict.windowSize = 0x1000
  dict.maxMatchAmount = 0x1000
  
  if comp:
    dest.write("COMP")
    destPtr += 4
  
  # write header: magic code and decompressed length
  if srcLen <= 0xffffff:
    dest.write((0x11 or (srcLen << 8)).int32)
  else:
    dest.write(0x11.byte)
    dest.write(srcLen.int32)
    destPtr += 4
  
  # start compression
  
  while srcPtr < srcLen:
    var buffer = newStringStream("")
    var flag:byte = 0
    
    for i in countdown(7, 0):
      var match = dict.search(srcString, srcPtr, srcLen)
      
      if match[1] > 0:
        # there is a match
        flag = flag or (1 << i).byte
        
        # how many bytes will the match take up?
        if match[1] <= 0xf + 1:
          # 2 bytes
          buffer.write(((((match[1] - 1) and 0xF) << 4) or (((match[0] - 1) and 0xFFF) >> 8)).byte)
          buffer.write(((match[0] - 1) and 0xFF).byte)
        elif match[1] <= 0xff + 17:
          # 3 bytes
          buffer.write((((match[1] - 17) and 0xFF) >> 4).byte)
          buffer.write(((((match[1] - 17) and 0xF) << 4) or (((match[0] - 1) and 0xFFF) >> 8)).byte)
          buffer.write(((match[0] - 1) and 0xFF).byte)
        else:
          # 4 bytes
          buffer.write((0x10 or (((match[1] - 273) and 0xFFFF) >> 12)).byte)
          buffer.write((((match[1] - 273) and 0xFFF) >> 4).byte)
          buffer.write(((((match[1] - 273) and 0xF) << 4) or (((match[0] - 1) and 0xFFF) >> 8)).byte)
          buffer.write(((match[0] - 1) and 0xFF).byte)
        
        dict.addEntryRange(srcString, srcPtr, match[1])
        dict.slideWindow(match[1])
        srcPtr += match[1]
      
      else:
        # there is not a match
        buffer.write(srcString[srcPtr])
        
        dict.addEntry(srcString, srcPtr)
        dict.slideWindow(1)
        srcPtr += 1
    
      # check if we reached the end of the file
      if srcPtr >= srcLen:
        break
    
    dest.write(flag)
    dest.write(buffer.data)
    destPtr += buffer.data.len + 1

proc isCOMP*(filePath:string): bool =
  let stream = openFileStream(filePath, fmRead)
  defer: stream.close()
  return stream.readStr(4) == "COMP"

# when isMainModule:
#   decompress("02_rng_original.fnt", "02_rng_test_decompressed.fnt")
#   let actual = readFile("02_rng_test_decompressed.fnt")
#   let expected = readFile("02_rng_decompressed.fnt")
#   assert(actual == expected)
  