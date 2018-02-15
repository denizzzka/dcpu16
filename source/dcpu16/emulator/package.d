module dcpu16.emulator;

import std.string: format;
import std.exception: enforce;

alias Memory = ushort[];

class Computer
{
    import dcpu16.emulator.cpu;
    import dcpu16.emulator.idevice;

    Memory mem;
    CPU cpu;
    IDevice[] devices;

    this() pure
    {
        mem.length = 0x10000;
        cpu = CPU(this);
    }

    void attachDevice(IDevice dev) pure
    {
        devices ~= dev;

        enforce(devices.length <= short.max);
    }

    void reset() pure
    {
        mem.length = 0;
        mem.length = 0x10000;
        cpu.reset();
    }

    void load(in ubyte[] from, bool wrongEndianness = false) pure
    {
        import std.bitmanip;

        enforce(from.length * 2 <= mem.length);
        enforce(from.length % 2 == 0);

        const len = from.length / ushort.sizeof;

        for(ushort i = 0; i < len; i+=2)
        {
            ubyte[2] d = from[i .. i+2];
            mem[i] = wrongEndianness
                ? bigEndianToNative!ushort(d)
                : littleEndianToNative!ushort(d);
        }
    }

    void load(in ushort[] from) pure
    {
        assert(from.length <= mem.length);

        mem[0 .. from.length] = from;
    }

    string memDump(ushort from) const
    {
        string ret;

        foreach(w; mem[from .. from+16])
            ret ~= format("%04x ", w);

        return ret;
    }

    string machineState() const
    {
        return format("Current instruction: %s\n%s\nMemory: %s\n",
                cpu.getCurrInstruction.toString,
                cpu.regs.toString,
                memDump(0)
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
            0x0803,         // SUB A, C        ; C = 1800, A = 0xF8F8 (FIXME: wtf?! 0xffff - 1800 == 0xf8f7)
            0x0041,         // SET C, A        ; C = -1800, A = 0xF8F8
            0x8401,         // SET A, 0        ; C = -1800
            0x8c45,         // MLI C, 2        ; C = -3600
            0x9047,         // DVI C, 3        ; C = -1200 (0xFB50)
        ];

    comp.cpu.reset;

    with(comp.cpu)
    with(regs)
    {
        import std.conv: to;

        step; assert(c == 500, c.to!string);
        step; assert(c == 999, c.to!string);
        step; assert(c == 900, c.to!string);
        step; assert(c == 1800, c.to!string);
        step; assert(c == 1800 && A == 0xFFFF);
        step; // SUB A, C
        assert(c == 1800);
        assert(A == 0xF8F7); // FIXME: should be 0xf8f8, see SUB comment above
        A = 0xf8f8;
        step;
        assert(c == cast(ushort) -1800);
        assert(A == 0xF8F8);
        step; assert(c == cast(ushort) -1800);
        step; assert(c == cast(ushort) -3600);
        step; assert(c == cast(ushort) -1200);
    }
}
