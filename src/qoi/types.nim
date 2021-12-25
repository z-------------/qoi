# Copyright (c) 2021 Zack Guard
# 
# This software is released under the MIT License.
# https://opensource.org/licenses/MIT

type
  QoiDesc* = object
    width*: uint
    height*: uint
    channels*: uint8
    colorspace*: uint8
