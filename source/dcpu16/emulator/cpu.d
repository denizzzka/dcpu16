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
}

import std.bitmanip: bitfields;
import dcpu16.emulator;
import std.string: format;

pure struct CPU
{
    import dcpu16.emulator.exception;

    Computer computer;
    Registers regs;
    InteruptQueue intQueue;
    bool isBurning;

    this(Computer c) pure
    {
        computer = c;
    }

    ref inout(Memory) mem() inout pure
    {
        return computer.mem;
    }

    void reset() pure
    {
        regs.reset;
        intQueue.reset;
    }

    void step()
    {
        auto ins = getCurrInstruction;
        regs.pc++;
        executeInstruction(ins);
    }

    Instruction getCurrInstruction() const pure
    {
        return Instruction(mem[regs.pc]);
    }

    private void executeInstruction(ref Instruction ins)
    {
        if(ins.opcode != Opcode.special)
            performBasicInstruction(ins);
        else
            performSpecialInstruction(ins);
    }

    private void complainWrongOpcode(in Instruction ins) pure
    {
        throw new Dcpu16Exception("Wrong opcode", ins, computer, __FILE__, __LINE__);
    }

    private void complainWrongDeviceNum(in Instruction ins) pure
    {
        throw new Dcpu16Exception("Wrong device number", ins, computer, __FILE__, __LINE__);
    }

    private void performBasicInstruction(ref Instruction ins) pure
    {
        if(ins.opcode > Opcode.STD)
            complainWrongOpcode(ins);

        int r;

        const ushort a = *decodeOperand(ins.a, ins, true);
        ushort* b_ptr = decodeOperand(ins.b, ins, false);
        const b = *b_ptr;

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
            case IFB: if(!((b & a) != 0)) conditionalSkip; return;
            case IFC: if(!((b & a) == 0)) conditionalSkip; return;
            case IFE: if(!(b == a)) conditionalSkip; return;
            case IFN: if(!(b != a)) conditionalSkip; return;
            case IFG: if(!(b > a)) conditionalSkip; return;
            case IFA: if(!(cast(short)b > cast(short)a)) conditionalSkip; return;
            case IFL: if(!(b < a)) conditionalSkip; return;
            case IFU: if(!(cast(short)b < cast(short)a)) conditionalSkip; return;
            case ADX: r = b + a + ex; ex = (r >>> 16) ? 1 : 0; break;
            case SBX: r = b - a + ex; auto under = cast(ushort) r >> 16; ex = under ? 0xffff : 0; break;
            case STI: r = b; i++; j++; break;
            case STD: r = b; i--; j--; break;

            case unused_0x18:
            case unused_0x19:
            case unused_0x1c:
            case unused_0x1d:
                complainWrongOpcode(ins);
        }

        if(ins.b < 0x1f) // operand is not literal value
            *b_ptr = cast(ushort) r;
    }

    private void conditionalSkip() pure
    {
        // Next instruction
        auto i = Instruction(mem[regs.pc]);

        regs.pc++;

        // Add PC for each "next word" operand
        if(is5bitNextWordOperand(cast(ubyte) i.a)) regs.pc++;
        if(is5bitNextWordOperand(cast(ubyte) i.b)) regs.pc++;
    }

    private static bool is5bitNextWordOperand(ubyte o) pure
    {
        return
            (o & 0b11110) == 0b11110 || // [next word] or next word (literal)
            (o & 0b11000) == 0b10000; // [some_register + next word]
    }

    private void performSpecialInstruction(ref Instruction ins)
    {
        ushort* a_ptr = decodeOperand(ins.a, ins, true);
        ushort a = *a_ptr;

        with(SpecialOpcode)
        with(regs)
        switch(ins.spec_opcode)
        {
            case JSR: push(pc); pc = a; return;
            case INT: isBurning = intQueue.addInterruptOrBurnOut(a); return;
            case IAG: a = ia; break;
            case IAS: ia = a; return;
            case RFI:
                intQueue.isTriggeringEnabled = false;
                A = pop();
                pc = pop();
                return;
            case IAQ: intQueue.isTriggeringEnabled = (a == 0); return;
            case HWN: a = cast(ushort) computer.devices.length; return;
            case HWQ:
                if(a >= computer.devices.length) complainWrongDeviceNum(ins);
                auto dev = computer.devices[a];
                A = cast(ushort) dev.id;
                B = dev.id >>> 16;
                c = dev.ver;
                x = cast(ushort) dev.manufacturer;
                y = dev.manufacturer >>> 16;
                return;
            case HWI:
                if(a >= computer.devices.length) complainWrongDeviceNum(ins);
                computer.devices[a].handleHardwareInterrupt(computer);
                return;
            case reserved:
            default:
                complainWrongOpcode(ins);
        }

        if(ins.a < 0x1f) // operand is not literal value
            *a_ptr = cast(ushort) a;
    }

    private void push(ushort val) pure
    {
        regs.sp--;
        mem[regs.sp] = val;
    }

    private ushort pop() pure
    {
        return mem[regs.sp++];
    }

    private ushort* decodeRegisterOfOperand(in ushort operand) pure
    {
        assert(operand <= 7);

        return &regs.asArr[operand];
    }

    private ushort* decodeOperand(ref ushort operand, in Instruction ins, bool isA) pure
    {
        if(operand > 0x3f)
            throw new Dcpu16Exception("Unknown operand", ins, computer, __FILE__, __LINE__);

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
                assert(isA, "Bigger than 5 bit b operand");
                operand -= 0x21;
                return &operand;
        }
    }

    string regsToString() const
    {
        import std.string;

        with(regs)
        {
            return format!
                "A:%04x  B:%04x  C:%04x  X:%04x  Y:%04x  Z:%04x  I:%04x  J:%04x  SP:%04x  PC:%04x  EX:%04x  IA:%04x\n [%04x]  [%04x]  [%04x]  [%04x]  [%04x]  [%04x]  [%04x]  [%04x]   [%04x]   [%04x]   [%04x]   [%04x]"
                (
                    A, B, c, x, y, z, i, j, sp, pc, ex, ia,
                    mem[A], mem[B], mem[c], mem[x], mem[y], mem[z],
                    mem[i], mem[j], mem[sp], mem[pc], mem[ex], mem[ia]
                );
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

private struct InteruptQueue
{
    private ushort[] queue; //TODO: It should be replaced by a more faster mechanism
    bool isTriggeringEnabled = true;

    bool addInterruptOrBurnOut(ushort msg) pure
    {
        if(queue.length > 256)
            return true;

        queue ~= msg;

        return false;
    }

    void reset() pure
    {
        this = InteruptQueue();
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

enum SpecialOpcode : ubyte
{
    reserved,
    JSR, /// pushes the address of the next instruction to the stack, then sets PC to a
    INT = 0x08, /// triggers a software interrupt with message a
    IAG, /// sets a to IA
    IAS, /// sets IA to a
    RFI, /// disables interrupt queueing, pops A from the stack, then pops PC from the stack
    IAQ,    /** if a is nonzero, interrupts will be added to the queue instead of triggered.
                if a is zero, interrupts will be triggered as normal again */
    HWN = 0x10, /// sets a to number of connected hardware devices
    HWQ,    /** sets A, B, C, X, Y registers to information about hardware a
                A+(B<<16) is a 32 bit word identifying the hardware id
                C is the hardware version
                X+(Y<<16) is a 32 bit word identifying the manufacturer
            */
    HWI, /// sends an interrupt to hardware a
}

struct Instruction
{
    ushort a; //TODO: rename to operandA
    union
    {
        ushort b; //TODO: rename to operandB
        SpecialOpcode spec_opcode;
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

    string toString() const pure
    {
        import std.conv: to;

        if(opcode == 0) // special opcode
        {
            return
                format!"special opcode=%02x (%s), opA=%02x"
                (spec_opcode, spec_opcode.to!string, a);
        }
        else
        {
            return
                format!"opcode=%02x (%s), opA=%02x, opB=%02x"
                (opcode, opcode.to!string, a, b);
        }
    }
}

pure unittest
{
    auto comp = new Computer;
    auto cpu = CPU(comp);
    cpu.regs.x = 123;
    comp.mem[123] = 456;

    Instruction i1;
    Instruction i2;

    i1.b = 0x03;
    i2.b = 0x0b;
    assert(*cpu.decodeOperand(i1.b, i1, false) == 123, "1");
    assert(*cpu.decodeOperand(i2.b, i2, false) == 456, "2");

    // literal values:
    i1.a = 0x20;
    i2.a = 0x3f;
    assert(*cpu.decodeOperand(i1.a, i1, true) == cast(ushort) -1);
    assert(*cpu.decodeOperand(i2.a, i2, true) == 30);
}
