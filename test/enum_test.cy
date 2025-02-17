-- Copyright (c) 2023 Cyber (See LICENSE)

import t 'test'

type Animal enum:
    case Bear
    case Tiger

-- enum to int.
my n = Animal.Tiger
t.eq(int(n), 1)

-- Using enum declared afterwards.
n = Animal2.Tiger
t.eq(int(n), 1)

-- Reassign using symbol literal.
n = Animal2.Tiger
n = .Dragon
t.eq(int(n), 2)

type Animal2 enum:
    case Bear
    case Tiger
    case Dragon