# Copyright (c) 2021 Zack Guard
# 
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT

type
  Rgba* = array[4, uint8]

const
  R* = 0
  G* = 1
  B* = 2
  A* = 3

const
  HeaderSize* = 14
  IndexSize* = 64
  Padding* = [0'u8, 0'u8, 0'u8, 0'u8, 0'u8, 0'u8, 0'u8, 1'u8]
  Magic* = ('q'.uint32 shl 24) or ('o'.uint32 shl 16) or ('i'.uint32 shl 8) or 'f'.uint32
  PixelsMax* = 400000000.uint32
  OpIndex* = 0x00 # 00xxxxxx
  OpDiff* = 0x40  # 01xxxxxx
  OpLuma* = 0x80  # 10xxxxxx
  OpRun* = 0xc0   # 11xxxxxx
  OpRgb* = 0xfe   # 11111110
  OpRgba* = 0xff  # 11111111
  Mask2* = 0xc0   # 11000000
  InitialPixel* = [0'u8, 0'u8, 0'u8, 255'u8]

func postInc*[T](x: var T; d: T = 1): T =
  let tmp = x
  x += d
  tmp

func `+@`*[T; I: SomeInteger](p: ptr T; offset: I): ptr T =
  cast[ptr T](cast[ByteAddress](p) + ByteAddress(offset) * sizeof(T))

func `[]`*[T; I: SomeInteger](base: ptr T; idx: I): T =
  let p = base +@ idx
  p[]

func `[]=`*[T](base: ptr T; idx: int; v: T) =
  let p = base +@ idx
  p[] = v

template colorHash*(c: Rgba): uint8 =
  c[R] * 3 + c[G] * 5 + c[B] * 7 + c[A] * 11
