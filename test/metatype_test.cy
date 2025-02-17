import t 'test'

-- id()
t.eq(typeof(none).id(), 0)
t.eq(typeof(true).id(), 1)
t.eq(typeof(false).id(), 1)
t.eq(typeof(error.err).id(), 2)
t.eq(typeof('abc').id(), 16)
t.eq(typeof('abc🦊').id(), 16)
t.eq(typeof(.abc).id(), 6)
t.eq(typeof(123).id(), 7)
t.eq(typeof(123.0).id(), 8)
t.eq(typeof([]).id(), 10)
t.eq(typeof([:]).id(), 12)

-- Referencing type object.
type Foo object:
    var a float
var foo = [Foo a: 123]
t.eq(typeof(foo), Foo)

-- Referencing builtin types.
t.eq((any).id(), 26)
t.eq((bool).id(), 1)
t.eq((float).id(), 8)
t.eq((int).id(), 7)
t.eq((string).id(), 16)
t.eq((array).id(), 17)
t.eq((symbol).id(), 6)
t.eq((List).id(), 10)
t.eq((Map).id(), 12)
t.eq((pointer).id(), 22)
t.eq((error).id(), 2)
t.eq((Fiber).id(), 18)
t.eq((metatype).id(), 23)

-- Referencing type name path.
import os
t.eq(typesym(os.CArray), .metatype)