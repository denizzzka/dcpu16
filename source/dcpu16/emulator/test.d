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

unittest
{
    enum str = import("self-copy.bin");
    auto blob = cast(ubyte[]) str;

    auto comp = new Computer();
    comp.load(blob, true);

    foreach(_; 0 .. 4000)
    {
        //~ import std.stdio;
        //~ comp.machineState.writeln;
        //~ comp.cpu.step;
    }

    import std.algorithm.comparison;

    //~ assert(equal(comp.mem[0 .. blob.length], comp.mem[blob.length .. blob.length*2]));
}
