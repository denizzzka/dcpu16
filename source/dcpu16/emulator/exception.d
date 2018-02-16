module dcpu16.emulator.exception;

import std.exception;

class Dcpu16Exception : Exception
{
    this(string msg, string file, size_t line) pure @safe
    {
        super(msg, file, line);
    }
}
