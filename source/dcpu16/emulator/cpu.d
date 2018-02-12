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

    void reset() pure
    {
        this = Registers();
    }
}

import dcpu16.emulator: Memory;

struct CPU
{
    Memory mem;
    Registers regs;

    this(ref Memory m) pure
    {
        mem = m;
    }

    void reset() pure
    {
        regs.reset;
    }

    Instruction currInstr() const
    {
        return Instruction(&this, mem[regs.pc]);
    }

    private ushort decodeRegisterOfOperand(uint operand) const pure // TODO: arg should be ubyte type
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

    private ushort decodeOperand(ubyte operand, bool isA) const pure
    {
        import std.exception: enforce;

        // Operands codes boundaries:
        enum directRegister = 0x07;
        enum indirectRegister = 0x0f;
        enum IndirectNextWordPlusRegister = 0x17;
        enum literalValue = 0x3f;

        enforce(operand <= literalValue, "Unknown operand");

        if(operand <= directRegister)
        {
            return decodeRegisterOfOperand(operand);
        }
        else if(operand <= indirectRegister)
        {
            return mem[decodeRegisterOfOperand(operand - directRegister)];
        }
        else if(operand <= IndirectNextWordPlusRegister)
        {
            ushort nextValue = mem[regs.pc+1];
            size_t address = nextValue + decodeRegisterOfOperand(operand - indirectRegister);
            return mem[address];
        }

        assert(operand != 0x18, "Unimplemented");
        assert(operand != 0x19, "Unimplemented");
        assert(operand != 0x1a, "Unimplemented");

        with(regs)
        switch(operand)
        {
            case 0x1b:
                return sp;

            case 0x1c:
                return pc;

            case 0x1d:
                return ex;

            case 0x1e: // [next word]
                return mem[ mem[pc+1] ];

            case 0x1f: // next word (literal)
                return mem[pc+1];

            default:
                break;
        }

        assert(operand > 0x1f);

        // literal values:
        operand -= 0x21;

        return operand;
    }
}

pure unittest
{
    Memory mem = new ushort[0x10000];
    auto cpu = CPU(mem);
    cpu.regs.x = 123;
    mem[123] = 456;

    assert(cpu.decodeOperand(0x03, false) == 123, "1");
    assert(cpu.decodeOperand(0x0a, false) == 456, "2");

    // literal values:
    assert(cpu.decodeOperand(0x20, true) == cast(ubyte) -1);
    assert(cpu.decodeOperand(0x3f, true) == 30);
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
    Memory mem = new ushort[0x10000];
    auto cpu = CPU(mem);
    auto i = Instruction(&cpu, 0b11111);

    assert(i.opcode == 0b11111);
    assert(i.a == 0);
    assert(i.b == 0);
}
