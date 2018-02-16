module dcpu16.emulator.test;

import dcpu16.emulator;

unittest
{
    enum blob = import("test.bin");

    auto comp = new Computer();
    comp.load(cast(ubyte[]) blob, true);

    foreach(_; 0 .. 4000)
    {
        //~ import std.stdio;
        //~ comp.machineState.writeln;
        comp.cpu.step;
    }
}
