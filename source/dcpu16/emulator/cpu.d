module dcpu16.emulator.cpu;

pure:

struct Registers
{
    ushort a;
    ushort b;
    ushort c;
    ushort x;
    ushort y;
    ushort z;
    ushort i;
    ushort j;
    ushort sp;
    ushort pc; /// Program counter
    ushort ex;
    ushort ia;

    void reset()
    {
        this = Registers();
    }
}

struct CPU
{
    import dcpu16.emulator: Memory;

    Memory* mem;
    Registers regs;

    this(Memory* m) pure
    {
        mem = m;
    }

    void reset()
    {
        regs.reset;
    }

    Instruction currInstr() const
    {
        return Instruction((*mem)[regs.pc]);
    }
}

struct Instruction
{
    this(ushort word0)
    {
    }
}
