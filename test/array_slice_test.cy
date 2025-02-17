-- Copyright (c) 2023 Cyber (See LICENSE)

-- Same tests as array.cy except using a slice.

import t 'test'

var arr = array('abc🦊xyz🐶')
arr = arr[0..]  -- Sets up the slice.
t.eq(arr, array('abc🦊xyz🐶'))

-- Sets up the slice
var upper = array('ABC🦊XYZ🐶')[0..]

-- index operator
t.eq(try arr[-1], error.OutOfBounds)
-- t.eq(arr[1-], 182)
-- t.eq(arr[4-], 240)
t.eq(arr[0], 97)
t.eq(arr[3], 240)
t.eq(try arr[14], error.OutOfBounds)

-- slice operator
t.eq(arr[0..], array('abc🦊xyz🐶'))
t.eq(arr[7..], array('xyz🐶'))
t.eq(arr[10..], array('🐶'))
t.eq(try arr[-1..], error.OutOfBounds)
t.eq(try arr[..-1], error.OutOfBounds)
t.eq(try arr[15..], error.OutOfBounds)
t.eq(try arr[..15], error.OutOfBounds)
t.eq(try arr[14..15], error.OutOfBounds)
t.eq(try arr[3..1], error.OutOfBounds)
t.eq(arr[14..], array(''))
t.eq(arr[..0], array(''))
t.eq(arr[..7], array('abc🦊'))
t.eq(arr[..10], array('abc🦊xyz'))
t.eq(arr[..14], array('abc🦊xyz🐶'))
t.eq(arr[0..0], array(''))
t.eq(arr[0..1], array('a'))
t.eq(arr[7..14], array('xyz🐶'))
t.eq(arr[10..14], array('🐶'))
t.eq(arr[14..14], array(''))

-- concat()
t.eq(arr.concat(array('123')), array('abc🦊xyz🐶123'))

-- decode()
t.eq(arr.decode(), 'abc🦊xyz🐶')
t.eq(arr.decode().isAscii(), false)
t.eq(array('abc').decode(), 'abc')
t.eq(array('abc').decode().isAscii(), true)
t.eq(try array('').insertByte(0, 255).decode(), error.Unicode)

-- endsWith()
t.eq(arr.endsWith(array('xyz🐶')), true)
t.eq(arr.endsWith(array('xyz')), false)

-- find()
t.eq(arr.find(array('bc🦊')), 1)
t.eq(arr.find(array('xy')), 7)
t.eq(arr.find(array('bd')), none)
t.eq(arr.find(array('ab')), 0)

-- findAnyByte()
t.eq(arr.findAnyByte(array('a')), 0)
t.eq(arr.findAnyByte(array('xy')), 7)
t.eq(arr.findAnyByte(array('ef')), none)

-- findByte()
t.eq(arr.findByte(`a`), 0)
t.eq(arr.findByte(`x`), 7)
t.eq(arr.findByte(`d`), none)
t.eq(arr.findByte(97), 0)
t.eq(arr.findByte(100), none)

-- fmt()
t.eq(arr.fmt(.b), '0110000101100010011000111111000010011111101001101000101001111000011110010111101011110000100111111001000010110110')
t.eq(arr.fmt(.o), '141142143360237246212170171172360237220266')
t.eq(arr.fmt(.d), '097098099240159166138120121122240159144182')
t.eq(arr.fmt(.x), '616263f09fa68a78797af09f90b6')

-- getByte()
t.eq(arr.getByte(0), 97)
t.eq(arr.getByte(3), 240)
t.eq(arr.getByte(4), 159)
t.eq(arr.getByte(10), 240)
t.eq(arr.getByte(13), 182)
t.eq(try arr.getByte(-1), error.OutOfBounds)
t.eq(try arr.getByte(14), error.OutOfBounds)

-- getInt()
var iarr = array('')
iarr = iarr.insertByte(0, 0x5a)
iarr = iarr.insertByte(1, 0xf1)
iarr = iarr.insertByte(2, 0x06)
iarr = iarr.insertByte(3, 0x04)
iarr = iarr.insertByte(4, 0x5e)
iarr = iarr.insertByte(5, 0xd2)
t.eq(iarr[0..].getInt(0, .big), 99991234567890)
t.eq(iarr.getInt(0, .little), -50173740388006)

-- getInt32()
iarr = array('')
iarr = iarr.insertByte(0, 0x49)
iarr = iarr.insertByte(1, 0x96)
iarr = iarr.insertByte(2, 0x02)
iarr = iarr.insertByte(3, 0xD2)
t.eq(iarr[0..].getInt32(0, .big), 1234567890)
t.eq(iarr[0..].getInt32(0, .little), 3523384905)

-- insertByte()
t.eq(arr.insertByte(2, 97), array('abac🦊xyz🐶'))

-- insert()
t.eq(try arr.insert(-1, array('foo')), error.OutOfBounds)
t.eq(arr.insert(0, array('foo')), array('fooabc🦊xyz🐶'))
t.eq(arr.insert(3, array('foo🦊')), array('abcfoo🦊🦊xyz🐶'))
t.eq(arr.insert(10, array('foo')), array('abc🦊xyzfoo🐶'))
t.eq(arr.insert(14, array('foo')), array('abc🦊xyz🐶foo'))
t.eq(try arr.insert(15, array('foo')), error.OutOfBounds)

-- len()
t.eq(arr.len(), 14)

-- repeat()
t.eq(try arr.repeat(-1), error.InvalidArgument)
t.eq(arr.repeat(0), array(''))
t.eq(arr.repeat(1), array('abc🦊xyz🐶'))
t.eq(arr.repeat(2), array('abc🦊xyz🐶abc🦊xyz🐶'))

-- replace()
t.eq(arr.replace(array('abc🦊'), array('foo')), array('fooxyz🐶'))
t.eq(arr.replace(array('bc🦊'), array('foo')), array('afooxyz🐶'))
t.eq(arr.replace(array('bc'), array('foo🦊')), array('afoo🦊🦊xyz🐶'))
t.eq(arr.replace(array('xy'), array('foo')), array('abc🦊fooz🐶'))
t.eq(arr.replace(array('xyz🐶'), array('foo')), array('abc🦊foo'))
t.eq(arr.replace(array('abcd'), array('foo')), array('abc🦊xyz🐶'))

-- split()
var res = array('abc,🐶ab,a')[0..].split(array(','))
t.eq(res.len(), 3)
t.eq(res[0], array('abc'))
t.eq(res[1], array('🐶ab'))
t.eq(res[2], array('a'))

-- trim()
t.eq(arr.trim(.left, array('a')), array('bc🦊xyz🐶'))
t.eq(arr.trim(.right, array('🐶')), array('abc🦊xyz'))
t.eq(arr.trim(.ends, array('a🐶')), array('bc🦊xyz'))

-- startsWith()
t.eq(arr.startsWith(array('abc🦊')), true)
t.eq(arr.startsWith(array('bc🦊')), false)