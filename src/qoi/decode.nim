# Copyright (c) 2021 Zack Guard
#
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT

import ./private/common
import ./types
import std/deques

func read32(bytes: Deque[uint8]; p: var int): uint32 =
  let
    a = bytes[postInc p].uint32
    b = bytes[postInc p].uint32
    c = bytes[postInc p].uint32
    d = bytes[postInc p].uint32
  a shl 24 or b shl 16 or c shl 8 or d

template read8(bytes: Deque[uint8]; p: var int): uint8 =
  bytes[postInc p]

type
  QoiDecodeContext* = object
    width*: uint
    height*: uint
    channels*: uint8
    colorspace*: uint8

    hasHeader: bool

    buf: Deque[uint8]

    px: Rgba
    run: uint32
    index: array[IndexSize, Rgba]
  UpdateCallback* = (proc (pixels: openArray[uint8]))

func initDecode*(channels = 0): QoiDecodeContext =
  result.buf = initDeque[uint8](HeaderSize)
  result.px = InitialPixel
  result.channels = channels.uint8

func processHeader(ctx: var QoiDecodeContext) =
  ## Process a complete read header
  var p = 0
  let headerMagic = ctx.buf.read32(p)
  ctx.width = ctx.buf.read32(p)
  ctx.height = ctx.buf.read32(p)
  let channels = ctx.buf.read8(p)
  if ctx.channels == 0:
    ctx.channels = channels
  ctx.colorspace = ctx.buf.read8(p)
  if ctx.width == 0 or ctx.height == 0 or ctx.channels < 3 or ctx.channels > 4 or ctx.colorspace > 1 or headerMagic != Magic or ctx.height >= PixelsMax div ctx.width:
    raise newException(ValueError, "invalid header")
  ctx.hasHeader = true

func processChunk(ctx: var QoiDecodeContext; callback: UpdateCallback) =
  ## Process a completely read chunk
  var p = 0
  let b1 = ctx.buf[0]
  if b1 == OpRgb:
    ctx.px[R] = ctx.buf.read8(p)
    ctx.px[G] = ctx.buf.read8(p)
    ctx.px[B] = ctx.buf.read8(p)
  elif b1 == OpRgba:
    ctx.px[R] = ctx.buf.read8(p)
    ctx.px[G] = ctx.buf.read8(p)
    ctx.px[B] = ctx.buf.read8(p)
    ctx.px[A] = ctx.buf.read8(p)
  elif (b1 and Mask2) == OpIndex:
    ctx.px = ctx.index[b1]
  elif (b1 and Mask2) == OpDiff:
    ctx.px[R] += ((b1 shr 4) and 0x03) - 2
    ctx.px[G] += ((b1 shr 2) and 0x03) - 2
    ctx.px[B] += ((b1 shr 0) and 0x03) - 2
  elif (b1 and Mask2) == OpLuma:
    let
      b2 = ctx.buf.read8(p)
      vg = (b1 and 0x3f) - 32
    ctx.px[R] += vg - 8 + ((b2 shr 4) and 0x0f)
    ctx.px[G] += vg
    ctx.px[B] += vg - 8 + ((b2 shr 0) and 0x0f)
  elif (b1 and Mask2) == OpRun:
    ctx.run = b1 and 0x3f
  else:
    raise newException(ValueError, "invalid chunk")

template addLast[T](d: Deque[T]; items: openArray[T]) =
  for item in items:
    d.addLast(item)

func update*(ctx: var QoiDecodeContext; data: openArray[uint8]; callback: UpdateCallback) =
  if not ctx.hasHeader:
    ctx.buf.addLast(data)
    if ctx.buf.len >= HeaderSize:
      ctx.processHeader()
