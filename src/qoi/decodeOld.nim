# Copyright (c) 2021 Zack Guard
#
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT
#
# Based on the C implementation by Dominic Szablewski (https://phoboslab.org) which is released under the following license:
#
# Copyright(c) 2021 Dominic Szablewski
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files(the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and / or sell copies
# of the Software, and to permit persons to whom the Software is furnished to do
# so, subject to the following conditions :
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import ./private/common
import ./types

func read32(bytes: ptr uint8; p: var int): uint32 =
  let
    a = bytes[postInc p].uint32
    b = bytes[postInc p].uint32
    c = bytes[postInc p].uint32
    d = bytes[postInc p].uint32
  a shl 24 or b shl 16 or c shl 8 or d

template read8(bytes: ptr uint8; p: var int): uint8 =
  bytes[postInc p]

proc decode*(bytes: ptr uint8; size: int; desc: var QoiDesc; channels = 0): seq[uint8] =
  var
    channels = channels.uint
    index: array[64, Rgba]
    px = InitialPixel
    p = 0
    run = 0'u32

  if bytes.isNil:
    raise newException(ValueError, "bytes is nil")
  if channels notin {0, 3, 4}:
    raise newException(ValueError, "invalid channels value")
  if size < HeaderSize + sizeof(Padding):
    raise newException(ValueError, "invalid size")

  let headerMagic = bytes.read32(p)
  desc.width = bytes.read32(p)
  desc.height = bytes.read32(p)
  desc.channels = bytes.read8(p)
  desc.colorspace = bytes.read8(p)

  if desc.width == 0 or desc.height == 0 or desc.channels < 3 or desc.channels > 4 or desc.colorspace > 1 or headerMagic != Magic or desc.height >= PixelsMax div desc.width:
    raise newException(ValueError, "invalid image")

  if channels == 0:
    channels = desc.channels

  let pxLen = desc.width * desc.height * channels
  result = newSeq[uint8](pxLen)

  let chunksLen = size - sizeof(Padding)
  for pxPos in countUp(0'u, pxLen - 1, channels):
    if run > 0:
      dec run
    elif p < chunksLen:
      let b1 = bytes.read8(p)
      if b1 == OpRgb:
        debugEcho "OpRgb"
        px[R] = bytes.read8(p)
        px[G] = bytes.read8(p)
        px[B] = bytes.read8(p)
      elif b1 == OpRgba:
        debugEcho "OpRgba"
        px[R] = bytes.read8(p)
        px[G] = bytes.read8(p)
        px[B] = bytes.read8(p)
        px[A] = bytes.read8(p)
      elif (b1 and Mask2) == OpIndex:
        debugEcho "OpIndex"
        px = index[b1]
      elif (b1 and Mask2) == OpDiff:
        debugEcho "OpDiff"
        px[R] += ((b1 shr 4) and 0x03) - 2
        px[G] += ((b1 shr 2) and 0x03) - 2
        px[B] += ((b1 shr 0) and 0x03) - 2
      elif (b1 and Mask2) == OpLuma:
        debugEcho "OpLuma"
        let
          b2 = bytes.read8(p)
          vg = (b1 and 0x3f) - 32
        px[R] += vg - 8 + ((b2 shr 4) and 0x0f)
        px[G] += vg
        px[B] += vg - 8 + ((b2 shr 0) and 0x0f)
      elif (b1 and Mask2) == OpRun:
        debugEcho "OpRun"
        run = b1 and 0x3f

      index[colorHash(px) mod 64] = px

    result[pxPos + 0] = px[R]
    result[pxPos + 1] = px[G]
    result[pxPos + 2] = px[B]
    if channels == 4:
      result[pxPos + 3] = px[A]
