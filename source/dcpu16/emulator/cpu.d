module dcpu16.emulator.cpu;

struct Registers
{
    union
    {
        ushort[8] asArr;

        struct
        {
            ushort A;
            ushort B;
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

    string toString() const
    {
        import std.string;

        return format!"A:%04x B:%04x C:%04x X:%04x Y:%04x Z:%04x I:%04x J:%04x SP:%04x PC:%04x EX:%04x IA:%04x"
            (A, B, c, x, y, z, i, j, sp, pc, ex, ia);
    }
}

import std.bitmanip: bitfields;
import dcpu16.emulator: Memory;
import std.string: format;

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
        auto ins = getCurrInstruction;
        regs.pc++;
        executeInstruction(ins);
    }

    Instruction getCurrInstruction() const
    {
        return Instruction(mem[regs.pc]);
    }

    private void executeInstruction(ref Instruction ins) pure
    {
        int r;

        if(ins.opcode != Opcode.special)
        {
            enforce(ins.opcode <= Opcode.STD, "Wrong opcode");

            ushort a = *decodeOperand(ins.a, true);
            ushort* b_ptr = decodeOperand(ins.b, false);
            ushort b = *b_ptr;

            with(Opcode)
            with(regs)
            final switch(ins.opcode) // TODO: replace it with "wire connection matrix"
            {
                case special: assert(false);
                case SET: r = a; break;
                case ADD: r = b + a; ex = r >>> 16; break;
                case SUB: r = b - a; ex = a > b ? 0xffff : 0; break;
                case MUL: r = b * a; ex = r >>> 16; break;
                case MLI: r = cast(short) a * cast(short) b; ex = cast(ushort) r >> 16; break;
                case DIV:
                    if (a==0)
                    {
                        r = 0;
                        ex = 0;
                    }
                    else
                    {
                        r = b / a;
                        ex = ((b << 16) / a) & 0xFFFF;
                    }
                    break;
                case DVI:
                    if (a==0)
                    {
                        r = 0;
                        ex = 0;
                    }
                    else
                    {
                        auto _a = cast(short) a;
                        auto _b = cast(short) b;

                        r = cast(short) _b / cast(short) _a;
                        ex = ((_b << 16) / _a) & 0xFFFF;
                    }
                    break;
                case MOD: r = a == 0 ? 0 : b % a; break;
                case MDI: r = a == 0 ? 0 : cast(short)b % cast(short)a; break;
                case AND: r = a & b; break;
                case BOR: r = a | b; break;
                case XOR: r = a ^ b; break;
                case SHR: r = b >>> a; ex = ((b<<16)>>>a) & 0xffff; break;
                case ASR: r = cast(short)b >> a; ex = ((b<<16)>>>a) & 0xffff; break;
                case SHL: r = b << a; ex = ((b<<a)>>>16) & 0xffff; break;
                case IFB: if(!((b & a) != 0)) pc++; return;
                case IFC: if(!((b & a) == 0)) pc++; return;
                case IFE: if(!(b == a)) pc++; return;
                case IFN: if(!(b != a)) pc++; return;
                case IFG: if(!(b > a)) pc++; return;
                case IFA: if(!(cast(short)b > cast(short)a)) pc++; return;
                case IFL: if(!(b < a)) pc++; return;
                case IFU: if(!(cast(short)b < cast(short)a)) pc++; return;
                case ADX: r = b + a + ex; ex = (r >>> 16) ? 1 : 0; break;
                case SBX: r = b - a + ex; auto under = cast(ushort) r >> 16; ex = under ? 0xffff : 0; break;
                case STI: r = b; i++; j++; break;
                case STD: r = b; i--; j--; break;

                case unused_0x18:
                case unused_0x19:
                case unused_0x1c:
                case unused_0x1d:
                    enforce("Wrong opcode");
            }

            if(ins.b < 0x1f) // operand is not literal value
                *b_ptr = cast(ushort) r;
        }
        else
            assert(false, "Unimplemented");
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
                enforce(isA, "Wrong B operand");
                ubyte tmp = cast(ubyte) operand;
                tmp -= 0x21;
                operand = tmp;
                return &operand;
        }
    }

    string stackDump() const
    {
        string ret;

        if(regs.sp != 0)
            for(ushort i = 0xffff; i >= regs.sp; i--)
                ret ~= format("%04x\n", mem[i]);

        return ret;
    }
}

enum Opcode : ubyte
{
    special, /// Special opcode
    SET, /// sets b to a
    ADD, /// sets b to b+a, sets EX to 0x0001 if there's an overflow, 0x0 otherwise
    SUB, /// sets EX to 0xffff if there's an underflow, 0x0 otherwise
    MUL, /// sets EX to ((b*a)>>16)&0xffff (treats b, a as unsigned)
    MLI, /// like MUL, but treat b, a as signed
    DIV, /// sets EX to ((b<<16)/a)&0xffff. if a==0, sets b and EX to 0 instead. (treats b, a as unsigned)
    DVI, /// like DIV, but treat b, a as signed. Rounds towards 0
    MOD, /// sets b to b%a. if a==0, sets b to 0 instead.
    MDI, /// like MOD, but treat b, a as signed. (MDI -7, 16 == -7)
    AND, /// sets b to b&a
    BOR, /// sets b to b|a
    XOR, /// sets b to b^a
    SHR, /// sets b to b>>>a, sets EX to ((b<<16)>>a)&0xffff (logical shift)
    ASR, /// sets b to b>>a, sets EX to ((b<<16)>>>a)&0xffff (arithmetic shift) (treats b as signed)
    SHL, /// sets b to b<<a, sets EX to ((b<<a)>>16)&0xffff
    IFB, /// performs next instruction only if (b&a)!=0
    IFC, /// performs next instruction only if (b&a)==0
    IFE, /// performs next instruction only if b==a
    IFN, /// performs next instruction only if b!=a
    IFG, /// performs next instruction only if b>a
    IFA, /// performs next instruction only if b>a (signed)
    IFL, /// performs next instruction only if b<a
    IFU, /// performs next instruction only if b<a (signed)
    unused_0x18,
    unused_0x19,
    ADX, /// sets b to b+a+EX, sets EX to 0x0001 if there is an overflow, 0x0 otherwise
    SBX, /// sets b to b-a+EX, sets EX to 0xFFFF if there is an underflow, 0x0 otherwise
    unused_0x1c,
    unused_0x1d,
    STI, /// sets b to a, then increases I and J by 1
    STD, /// sets b to a, then decreases I and J by 1
}

struct Instruction
{
    ushort a;
    union
    {
        ushort b;
        ushort spec_opcode;
    }
    Opcode opcode;

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
        opcode = cast(Opcode) u.opcode;
    }

    string toString() const
    {
        import std.conv: to;

        return format!"opcode=%02x (%s), opA=%02x, opB=%02x"
            (opcode, opcode.to!string, a, b);
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
