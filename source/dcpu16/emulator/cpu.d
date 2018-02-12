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

    void step()
    {
        auto curr = getCurrInstr();
    }

    private Instruction getCurrInstr()
    {
        return Instruction(mem[regs.pc]);
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

        private this(ushort w0) pure
        {
            word0 = w0;
        }
    }

    private ushort* decodeRegisterOfOperand(in uint operand) pure // TODO: arg should be ubyte type
    {
        with(regs)
        switch(operand)
        {
            case 0x00: return &a;
            case 0x01: return &b;
            case 0x02: return &c;
            case 0x03: return &x;
            case 0x04: return &y;
            case 0x05: return &z;
            case 0x06: return &i;
            case 0x07: return &j;

            default:
                assert(false);
        }
    }

    private ushort* decodeOperand(ref ushort operand, bool isA) pure
    {
        import std.exception: enforce;

        enforce(operand <= 0x3f, "Unknown operand");

        with(regs)
        switch(operand)
        {
            case 0x00: .. case 0x07: // register
                return decodeRegisterOfOperand(operand);

            case 0x08: .. case 0x0f: // [register]
                return &mem[ *decodeRegisterOfOperand(operand & 7) ];

            case 0x10: .. case 0x17: // [register + next word]
                return &mem[ *decodeRegisterOfOperand(operand & 7) + mem[regs.pc++] ];

            case 0x18: // PUSH / POP
                return isA ? &mem[sp++] : &mem[--sp];

            case 0x19: // PEEK
                return &mem[sp];

            case 0x1a: // PICK n
                return &mem[ sp + mem[pc+1] ];

            case 0x1b:
                return &sp;

            case 0x1c:
                return &pc;

            case 0x1d:
                return &ex;

            case 0x1e: // [next word]
                return &mem[ mem[pc++] ];

            case 0x1f: // next word (literal)
                return &mem[pc++];

            default: // literal values
                ubyte tmp = cast(ubyte) operand;
                tmp -= 0x21;
                operand = tmp;
                return &operand;
        }
    }
}

pure unittest
{
    Memory mem = new ushort[0x10000];
    auto cpu = CPU(mem);
    cpu.regs.x = 123;
    mem[123] = 456;

    ushort o1 = 0x03;
    ushort o2 = 0x0b;
    assert(*cpu.decodeOperand(o1, false) == 123, "1");
    assert(*cpu.decodeOperand(o2, false) == 456, "2");

    // literal values:
    ushort l1 = 0x20;
    ushort l2 = 0x3f;
    assert(*cpu.decodeOperand(l1, true) == cast(ubyte) -1);
    assert(*cpu.decodeOperand(l2, true) == 30);
}
