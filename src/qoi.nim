# Copyright (c) 2021 Zack Guard
# 
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT

import qoi/types
import qoi/decode
import qoi/encode

export types
export decode
export encode

when isMainModule:
  import pkg/nimPNG

  var decoder = initDecode()

  let f = open("testcard_rgba.qoi")
  const BufSize = 256
  var
    buf: array[BufSize, uint8]
    readSize: int
  while true:
    readSize = f.readBytes(buf, 0, BufSize)
    decoder.update(buf.toOpenArray(0, readSize - 1)) do (pixels: openArray[uint8]):
      debugEcho "got some pixels"
    if readSize < BufSize:
      break
  # let pixels = decode(bytes, data.len, desc)
  # if savePNG32("out2.png", pixels, desc.width.int, desc.height.int).isErr:
  #   echo "png error"
