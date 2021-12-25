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

func write32(bytes: ptr uint8; p: var int; v: uint) =
  bytes[postInc p] = ((0xff000000'u64 and v) shr 24).uint8
  bytes[postInc p] = ((0x00ff0000'u64 and v) shr 16).uint8
  bytes[postInc p] = ((0x0000ff00'u64 and v) shr 8).uint8
  bytes[postInc p] = ((0x000000ff'u64 and v) shr 0).uint8

template write32(bytes: var seq[uint8]; p: var int; v: uint): untyped =
  write32(addr bytes[0], p, v)

template write8(bytes: var seq[uint8]; p: var int; v: uint8) =
  bytes[postInc p] = v

proc encode*(pixels: ptr uint8; desc: var QoiDesc; outLen: var int): seq[uint8] =
  var
    p, run: int
    index: array[64, Rgba]
    pxPrev = InitialPixel
    px = pxPrev

  if pixels.isNil or desc.width == 0 or desc.height == 0 or desc.channels < 3 or desc.channels > 4 or desc.colorspace > 1 or desc.height >= PixelsMax div desc.width:
    raise newException(ValueError, "invalid input")

  let maxSize = desc.width * desc.height * (desc.channels + 1) + HeaderSize + sizeof(Padding).uint
  result = newSeq[uint8](maxSize)

  result.write32(p, Magic)
  result.write32(p, desc.width)
  result.write32(p, desc.height)
  result.write8(p, desc.channels)
  result.write8(p, desc.colorspace)

  let
    pxLen = desc.width * desc.height * desc.channels
    pxEnd = pxLen - desc.channels
    channels = desc.channels

  for pxPos in countUp(0'u, pxLen - 1, channels):
    px[R] = pixels[pxPos + 0]
    px[G] = pixels[pxPos + 1]
    px[B] = pixels[pxPos + 2]
    if channels == 4:
      px[A] = pixels[pxPos + 3]

    if px == pxPrev:
      inc run
      if run == 52 or pxPos == pxEnd:
        result.write8(p, OpRun or (run - 1).uint8)
        run = 0
    else:
      if run > 0:
        result.write8(p, OpRun or (run - 1).uint8)
        run = 0

      let indexPos = colorHash(px) mod 64
      if index[indexPos] == px:
        result.write8(p, OpIndex or indexPos)
      else:
        index[indexPos] = px
        if px[A] == pxPrev[A]:
          let
            vr = px[R].int - pxPrev[R].int
            vg = px[G].int - pxPrev[G].int
            vb = px[B].int - pxPrev[B].int
            vgR = vr - vg
            vgB = vb - vg
          if vr > -3 and vr < 2 and vg > -3 and vg < 2 and vb > -3 and vb < 2:
            result.write8(p,
              OpDiff or
              ((vr + 2) shl 4).uint8 or
              ((vg + 2) shl 2).uint8 or
              (vb + 2).uint8
            )
          elif vgR > -9 and vgR < 8 and vg > -33 and vg < 32 and vgB > -9 and vgB < 8:
            result.write8(p, OpLuma or (vg + 32).uint8)
            result.write8(p, (vgR + 8 shl 4).uint8 or (vgB + 8).uint8)
          else:
            result.write8(p, OpRgb)
            result.write8(p, px[R])
            result.write8(p, px[G])
            result.write8(p, px[B])
        else:
          result.write8(p, OpRgba)
          result.write8(p, px[R])
          result.write8(p, px[G])
          result.write8(p, px[B])
          result.write8(p, px[A])
    pxPrev = px

  for b in Padding:
    result.write8(p, b)
  outLen = p
