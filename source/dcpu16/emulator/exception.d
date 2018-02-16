module dcpu16.emulator.exception;

import std.exception;
import std.string;
import dcpu16.emulator.cpu: Instruction;

class Dcpu16Exception : Exception
{
    this(string msg, Instruction ins, string file, size_t line) pure
    {
        super(
            format("%s\n%s", msg, ins.toString),
            file,
            line
        );
    }
}
