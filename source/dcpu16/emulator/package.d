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
        import std.bitmanip : littleEndianToNative;

        enforce(from.length <= Memory.sizeof);
        enforce(from.length % 2 == 0);

        const len = from.length / ushort.sizeof;

        for(ushort i = 0; i < len; i+=2)
        {
            ubyte[2] d = from[i .. i+2];
            mem[i] = littleEndianToNative!ushort(d);
        }
    }
}

pure:

unittest
{
    auto c = new Computer();
    c.load(new ubyte[10]);
    c.reset();
}
