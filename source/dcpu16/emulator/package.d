module dcpu16.emulator;

alias Memory = ushort[];

class Computer
{
    import dcpu16.emulator.cpu;

    Memory mem;
    CPU cpu;

    this() pure
    {
        mem.length = 0x10000;
        cpu = CPU(mem);
    }

    void reset() pure
    {
        mem.length = 0;
        mem.length = 0x10000;
        cpu.reset();
    }

    void load (string filename)
    {
        import std.file;

        ubyte[] d = cast(ubyte[]) read(filename);

        load(d);
    }

    void load(ubyte[] from) pure
    {
        import std.exception: enforce;
        import std.bitmanip;

        enforce(from.length <= Memory.sizeof);
        enforce(from.length % 2 == 0);

        const len = from.length / ushort.sizeof;

        for(ushort i = 0; i < len; i+=2)
        {
            ubyte[2] d = from[i .. i+2];
            mem[i] = littleEndianToNative!ushort(d);
        }
    }

    string memDump() const
    {
        import std.string;

        string ret;

        for(auto i = 0; i < 16; i++)
            ret ~= format("%04x ", mem[i]);

        return ret;
    }
}

unittest
{
    import std.stdio;

    auto c = new Computer();
    c.mem[0 .. 3] =
        [
            0x8801, // set a, 1
            0x9002, // add a, 3 :loop
            0x8b81, // set pc, loop
        ];
    //~ c.load("examples/loop.bin");

    assert(c.mem[0] != 0, "First instruction is null");

    c.cpu.reset;

    foreach(i; 0 .. 10)
    {
        writeln("Loaded "~c.cpu.ins.toString);
        writeln(c.cpu.regs);
        writeln("Memory: "~c.memDump);
        c.cpu.step;
        writefln("Step %d executed", i);
    }

    c.reset;
}
