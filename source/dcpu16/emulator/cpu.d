module dcpu16.emulator.cpu;

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
    ushort sp; /// stack pointer
    ushort pc; /// program counter
    ushort ex; /// extra/excess
    ushort ia; /// interrupt address

    void reset()
    {
        this = Registers();
    }
}

import dcpu16.emulator: Memory;

struct CPU
{
    Memory* _mem;
    Registers regs;

    this(Memory* m) pure
    {
        _mem = m;
    }

    ref Memory mem() inout
    {
        return this.mem;
    }

    void reset()
    {
        regs.reset;
    }

    Instruction currInstr() const
    {
        return Instruction(&this, mem[regs.pc]);
    }

    private ushort decodeRegisterOperand(uint operand) const
    {
        with(regs)
        switch(operand)
        {
            case 0x00: return a;
            case 0x01: return b;
            case 0x02: return c;
            case 0x03: return x;
            case 0x04: return y;
            case 0x05: return z;
            case 0x06: return i;
            case 0x07: return j;

            default:
                assert(false);
        }
    }

    ushort decodeOperand(ubyte operand) const
    {
        if(operand <= 0x07) // Direct Register
            return decodeRegisterOperand(operand);
        else if(operand <= 0x0f) // Indirect Register
            return mem[decodeRegisterOperand(operand - 0x0f)];
        else if(operand <= 0x17) // Indirect Next Word plus Register
        {
            ushort nextValue = mem[regs.pc+1];
            size_t address = nextValue + decodeRegisterOperand(operand - 0x17);
            return mem[address];
        }
        else
            assert(false);
    }
}

unittest
{
    Memory mem;
    auto cpu = CPU(&mem);
    cpu.regs.x = 123;

    assert(cpu.decodeRegisterOperand(3) == 123);
}

struct Instruction
{
    import std.bitmanip: bitfields;

    union
    {
        ushort word0;

        mixin(bitfields!(
            ubyte, "opcode",    5,
            ubyte, "b",         5,
            ubyte, "a",         6,
        ));

        mixin(bitfields!(
            ubyte, "spec_zeroes",   5,
            ubyte, "spec_opcode",   5,
            ubyte, "spec_a",        6,
        ));
    }

    ushort word1;
    ushort word2;

    this(in CPU* mem, ushort w0) pure
    {
        word0 = w0;
    }
}

pure unittest
{
    Memory mem;
    auto cpu = CPU(&mem);
    auto i = Instruction(&cpu, 0b11111);

    assert(i.opcode == 0b11111);
    assert(i.a == 0);
    assert(i.b == 0);
}
