module dcpu16.emulator.test;

import dcpu16.emulator;

unittest
{
    enum blob = import("test.bin");

    auto comp = new Computer();
    comp.load(cast(ubyte[]) blob, true);

    foreach(_; 0 .. 4000)
    {
        comp.cpu.step;
    }
}

unittest
{
    enum blob = import("test_basic_stuff.bin");

    auto comp = new Computer();
    comp.load(cast(ubyte[]) blob, true);

    foreach(_; 0 .. 1000)
    {
        comp.cpu.step;
    }

    assert(comp.cpu.regs.x == 0x40);
}

unittest
{
    enum str = import("self-copy.bin");
    auto blob = cast(ubyte[]) str;

    auto comp = new Computer();
    comp.load(blob, true);

    const etalon = comp.mem[0x01 .. 0x19];

    foreach(_; 0 .. 1000)
    {
        comp.cpu.step;
    }

    import std.algorithm.comparison;

    foreach(n; 0 .. 8)
    {
        size_t offset = 1 + (etalon.length-1) * n;
        const copy = comp.mem[offset .. offset + etalon.length];

        assert(equal(etalon, copy));
    }
}
