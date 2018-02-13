module dcpu16.emulator;

import std.string: format;

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

    void load(ushort[] from) pure
    {
        assert(from.length <= mem.length);

        mem[0 .. from.length] = from;
    }

    string memDump() const
    {
        string ret;

        for(auto i = 0; i < 16; i++)
            ret ~= format("%04x ", mem[i]);

        return ret;
    }

    string machineState() const
    {
        return format("Current instruction: %s\n%s\nMemory: %s\n",
                cpu.getCurrInstruction.toString,
                cpu.regs.toString,
                memDump
            );
    }
}

unittest
{
    auto c = new Computer();
    c.mem[0 .. 3] =
        [
            0x8801, // set a, 1
            0x9002, // add a, 3 :loop
            0x8b81, // set pc, loop
        ];

    assert(c.mem[0] != 0, "First instruction is null");

    c.cpu.reset;

    foreach(i; 0 .. 16)
        c.cpu.step;

    assert(c.cpu.regs.A == 0x19);
    assert(c.cpu.regs.pc == 0x02);

    c.reset;
    assert(c.mem[0] == 0);
}

unittest
{
    auto comp = new Computer();
    comp.load =
        [
            // high-nerd.dasm16
            0x7c41, 0x01f4, // SET C, 500      ; C = 500
            0x7c42, 0x01f3, // ADD C, 499      ; C = 999
            0x7c43, 0x0063, // SUB C, 99       ; C = 900
            0x8c44,         // MUL C, 2        ; C = 1800
            0x8001,         // SET A, 0xFFFF   ; C = 1800, A = 0xFFFF
            0x0803,         // SUB A, C        ; C = 1800, A = 0xF8F8
            0x0041,         // SET C, A        ; C = -1800, A = 0xF8F8
            0x8401,         // SET A, 0        ; C = -1800
            0x8c45,         // MLI C, 2        ; C = -3600
            0x9047,         // DVI C, 3        ; C = -1200 (0xFB50)
        ];

    comp.cpu.reset;

    import std.stdio;

    with(comp.cpu.regs)
    {
        writeln(comp.machineState); comp.cpu.step; writeln(c); writeln(comp.machineState); assert(c == 500);
        comp.cpu.step; assert(c == 999);
    }
}
