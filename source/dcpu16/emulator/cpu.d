module dcpu16.emulator.cpu;

struct Registers
{
    union
    {
        ushort[8] asArr;

        struct
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
        }
    }

    void reset() pure
    {
        this = Registers();
    }
}

import dcpu16.emulator: Memory;

pure struct CPU
{
    import std.exception: enforce;

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
        Instruction curr = Instruction(mem[regs.pc]);
    }

    private void decodeOpcode(ref Instruction ins) pure
    {
        if(!ins.spec_zeroes)
        {
            ushort* a = decodeOperand(ins.a, true);
            ushort* b = decodeOperand(ins.b, false);

            switch(ins.opcode)
            {
                case 0x01: // SET
                    *b = *a;
                    break;

                case 0x02: // ADD
                    *b += *a;
                    regs.ex = *b + *a > ushort.max ?
                        regs.ex = 1 : 0;
                    break;

                default:
                    enforce("Opcode isn't defined");
            }
        }
        else
            assert("Unimplemented");
    }

    private ushort* decodeRegisterOfOperand(in ushort operand) pure
    {
        assert(operand <= 7);

        return &regs.asArr[operand];
    }

    private ushort* decodeOperand(ref ushort operand, bool isA) pure
    {
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

struct Instruction
{
    import std.bitmanip: bitfields;

    ushort a;
    ushort b;
    ubyte opcode;

    alias spec_zeroes = opcode;
    alias spec_opcode = b;

    private this(ushort w0) pure
    {
        union U
        {
            ushort word;

            mixin(bitfields!(
                ubyte, "opcode",    5,
                ubyte, "b",         5,
                ubyte, "a",         6,
            ));
        }

        U u = U(w0);

        a = u.a;
        b = u.b;
        opcode = u.opcode;
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
