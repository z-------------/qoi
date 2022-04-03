# Copyright (c) 2021 Zack Guard
#
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT

import ./private/common
import std/deques

const
  QoiCapacityFactor {.intdefine.} = 4 # Somewhat arbitrarily chosen. Each chunk consists of between 1 and 5 bytes. Most chunks produce 1 pixel each, except for runs which can produce up to 64 pixels. Each pixel consists of 3 or 4 bytes. If we ignore runs, the worst case is that each chunk is 1 byte and produces 4 bytes.

type
  Buf = Deque[uint8] or openArray[uint8]

func read32(bytes: Buf; p: var int): uint32 =
  let
    a = bytes[postInc p].uint32
    b = bytes[postInc p].uint32
    c = bytes[postInc p].uint32
    d = bytes[postInc p].uint32
  a shl 24 or b shl 16 or c shl 8 or d

template read8(bytes: Buf; p: var int): uint8 =
  bytes[postInc p]

type
  QoiDecodeContext* = object
    width*: uint
    height*: uint
    channels*: uint8
    colorspace*: uint8

    headerBytesNeeded: int

    buf: Deque[uint8]
    index: array[IndexSize, Rgba]
  UpdateCallback* = (proc (data: seq[uint8]))

func initDecode*(channels = 0): QoiDecodeContext =
  result.channels = channels.uint8
  result.headerBytesNeeded = HeaderSize
  result.buf = initDeque[uint8](HeaderSize)

func processHeader(ctx: var QoiDecodeContext) =
  ## Process a completely read header
  var p = 0
  let headerMagic = ctx.buf.read32(p)
  ctx.width = ctx.buf.read32(p)
  ctx.height = ctx.buf.read32(p)
  let channels = ctx.buf.read8(p)
  if ctx.channels == 0:
    ctx.channels = channels
  ctx.colorspace = ctx.buf.read8(p)
  if headerMagic != Magic or
      0 in {ctx.width, ctx.height} or
      ctx.channels notin {3, 4} or
      ctx.colorspace > 1 or
      ctx.height >= PixelsMax div ctx.width:
    raise newException(ValueError, "invalid header")

func processChunk(ctx: var QoiDecodeContext; buf: Buf; outData: var seq[uint8]) =
  ## Process a completely read chunk
  var
    pos = 0
    count = 1
    pixel = InitialPixel
  let b1 = buf[0]
  if b1 == OpRgb:
    pixel[R] = buf.read8(pos)
    pixel[G] = buf.read8(pos)
    pixel[B] = buf.read8(pos)
  elif b1 == OpRgba:
    pixel[R] = buf.read8(pos)
    pixel[G] = buf.read8(pos)
    pixel[B] = buf.read8(pos)
    pixel[A] = buf.read8(pos)
  elif (b1 and Mask2) == OpIndex:
    pixel = ctx.index[b1]
  elif (b1 and Mask2) == OpDiff:
    pixel[R] += ((b1 shr 4) and 0x03) - 2
    pixel[G] += ((b1 shr 2) and 0x03) - 2
    pixel[B] += ((b1 shr 0) and 0x03) - 2
  elif (b1 and Mask2) == OpLuma:
    let
      b2 = buf.read8(pos)
      vg = (b1 and 0x3f) - 32
    pixel[R] += vg - 8 + ((b2 shr 4) and 0x0f)
    pixel[G] += vg
    pixel[B] += vg - 8 + ((b2 shr 0) and 0x0f)
  elif (b1 and Mask2) == OpRun:
    count += (b1 and 0x3f).int
  else:
    raise newException(ValueError, "invalid chunk")
  ctx.index[colorHash(pixel) mod 64] = pixel
  for _ in 0..<count:
    if ctx.channels == 4:
      outData.add(pixel)
    else:
      outData.add(pixel[R..B])

template addLast[T](d: Deque[T]; items: openArray[T]) =
  for item in items:
    d.addLast(item)

func chunkSize(b1: uint8): int =
  ## The size of the chunk with the given first byte
  if b1 == OpRgb:
    4
  elif b1 == OpRgba:
    5
  elif (b1 and Mask2) in {OpIndex, OpDiff, OpRun}:
    1
  elif (b1 and Mask2) == OpLuma:
    2
  else:
    raise newException(ValueError, "invalid chunk")

func update*(ctx: var QoiDecodeContext; data: openArray[uint8]; callback: UpdateCallback) =
  var pos = 0

  # read the header
  if ctx.headerBytesNeeded > 0:
    let bytesToAdd = min(ctx.headerBytesNeeded, data.len)
    ctx.buf.addLast(data.toOpenArray(pos, pos.preInc(bytesToAdd) - 1))
    ctx.headerBytesNeeded = HeaderSize - ctx.buf.len
    if ctx.headerBytesNeeded == 0:
      ctx.processHeader()

  # read chunks
  var outData = newSeqOfCap[uint8](data.len * QoiCapacityFactor)
  if ctx.headerBytesNeeded == 0:
    # finish the current incomplete chunk
    if ctx.buf.len != 0:
      let
        bytesNeeded = chunkSize(ctx.buf[0]) - ctx.buf.len
        bytesToAdd = min(bytesNeeded, data.len)
      ctx.buf.addLast(data.toOpenArray(pos, pos.preInc(bytesToAdd) - 1))
      if bytesToAdd >= bytesNeeded:
        ctx.processChunk(ctx.buf, outData)
        ctx.buf.clear()
    # read complete chunks
    var size: int
    while data.len - pos >= 1 and (size = chunkSize(data[pos]); data.len - pos >= size):
      ctx.processChunk(data.toOpenArray(pos, pos.preInc(size) - 1), outData)
    # buffer trailing incomplete chunk
    if pos < data.len:
      ctx.buf.addLast(data.toOpenArray(pos, data.high))
