-- Copyright (c) 2023 Cyber (See LICENSE)

import t 'test'

-- Variable assignment.
var a = 1
t.eq(a, 1)

-- Overwrite existing var.
a = 1
a = 2
t.eq(a, 2)

-- Use existing var.
a = 1
var b = a + 2
t.eq(b, 3)

-- Using a variable that was conditionally assigned.
var f = func():
    my a = none
    if true:
        a = 1
    return a
t.eq(f(), 1)

-- Using a variable that was conditionally not assigned.
f = func():
    my a = none
    if false:
        a = 1
    return a
t.eq(f(), none)

-- Using a variable that was assigned in a loop.
f = func():
    my a = none
    for 2..3 -> i:
        a = i
    return a
t.eq(f(), 2)

-- Using a variable that was not assigned in a loop.
f = func():
    my a = none
    for 2..2 -> i:
        a = i
    return a
t.eq(f(), none)