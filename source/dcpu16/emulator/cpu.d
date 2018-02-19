module dcpu16.emulator.cpu;

version = CPUDebuggingMethods;

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
        }
    }

    ushort sp; /// stack pointer
    private ushort pc; /// program counter for internal purposes
    private ushort _pc; /// program counter available for users through getter/setter
    ushort ex; /// extra/excess
    ushort ia; /// interrupt address
    version(CPUDebuggingMethods) ushort ds; /// debug status

    /// program counter register
    ushort PC() const pure @property { return _pc; }
    /// ditto
    ushort PC(ushort v) pure @property
    {
        _pc = v;
        pc = v;
        return _pc;
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

    Registers regs;
    bool isBurning;
    private Computer computer;
    private InteruptQueue intQueue;

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

    /// Returns: clock cycles cost of executed step
    ubyte step()
    {
        if(intQueue.isTriggeringEnabled && !intQueue.empty)
        {
            auto msg = intQueue.pop;

            if(regs.ia)
                regs.PC = regs.ia;
        }

        Instruction ins = getCurrInstruction;
        regs.pc++;
        ubyte cycles = executeInstruction(ins);
        regs.PC = regs.pc;

        version(CPUDebuggingMethods)
        {
            if(testBreakpoint(regs.PC))
                regs.ds |= 1;
        }

        return cycles;
    }

    Instruction getCurrInstruction() const pure
    {
        return Instruction(mem[regs.PC]);
    }

    /// Returns: clock cycles cost of executed instruction
    private ubyte executeInstruction(in Instruction ins)
    {
        byte cost;

        if(!ins.isSpecialOpcode)
            performBasicInstruction(ins, cost);
        else
            performSpecialInstruction(ins, cost);

        assert(cost > 0);

        return cost;
    }

    private void complainWrongOpcode(in Instruction ins) pure
    {
        throw new Dcpu16Exception("Wrong opcode", computer, __FILE__, __LINE__);
    }

    private void complainWrongDeviceNum(in Instruction ins, ushort devNum) pure
    {
        throw new Dcpu16Exception(
                format("Wrong device number %04#x", devNum), computer, __FILE__, __LINE__
            );
    }

    private void performBasicInstruction(in Instruction ins, out byte cost) pure
    {
        scope(success)
        {
            byte t = opcodesCyclesCost[ins.basic_opcode];
            assert(t > 0);
            cost += t;
        }

        int r;

        ushort mutable = ins.a;
        const ushort a = *decodeOperand(mutable, true, cost);
        mutable = ins.b;
        ushort* b_ptr = decodeOperand(mutable, false, cost);
        const b = *b_ptr;

        with(Opcode)
        with(regs)
        switch(ins.basic_opcode)
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
            case IFB: if(!((b & a) != 0)) skip(cost); return;
            case IFC: if(!((b & a) == 0)) skip(cost); return;
            case IFE: if(!(b == a)) skip(cost); return;
            case IFN: if(!(b != a)) skip(cost); return;
            case IFG: if(!(b > a)) skip(cost); return;
            case IFA: if(!(cast(short)b > cast(short)a)) skip(cost); return;
            case IFL: if(!(b < a)) skip(cost); return;
            case IFU: if(!(cast(short)b < cast(short)a)) skip(cost); return;
            case ADX: r = b + a + ex; ex = (r >>> 16) ? 1 : 0; break;
            case SBX: r = b - a + ex; auto under = cast(ushort) r >> 16; ex = under ? 0xffff : 0; break;
            case STI: r = b; i++; j++; break;
            case STD: r = b; i--; j--; break;

            default:
                complainWrongOpcode(ins);
        }

        if(ins.b < 0x1f) // operand is not literal value
            *b_ptr = cast(ushort) r;
    }

    /// Skip (set pc to) next instruction
    private void skip(ref byte cost) pure
    {
        cost++;

        /// Next instruction
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

    private void performSpecialInstruction(in Instruction ins, byte cost)
    {
        scope(success)
        {
            byte t = specialOpcodesCyclesCost[ins.spec_opcode];
            assert(t > 0);
            cost += t;
        }

        ushort mutable_a = ins.a;
        ushort* a_ptr = decodeOperand(mutable_a, true, cost);
        ushort a = *a_ptr;

        with(SpecialOpcode)
        with(regs)
        switch(ins.spec_opcode)
        {
            case JSR: push(pc); pc = a; return;
            case INT: addInterruptOrBurnOut(a); return;
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
                if(a >= computer.devices.length) complainWrongDeviceNum(ins, a);
                auto dev = computer.devices[a];
                A = cast(ushort) dev.id;
                B = dev.id >>> 16;
                c = dev.ver;
                x = cast(ushort) dev.manufacturer;
                y = dev.manufacturer >>> 16;
                return;
            case HWI:
                if(a >= computer.devices.length) complainWrongDeviceNum(ins, a);
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

    private ushort* decodeRegisterOfOperand(in ushort operand) pure nothrow
    {
        assert(operand <= 7);

        return &regs.asArr[operand];
    }

    private ushort* decodeOperand(ref ushort operand, bool isA, ref byte cost) pure
    {
        if(operand > 0x3f)
            throw new Dcpu16Exception("Unknown operand", computer, __FILE__, __LINE__);

        with(regs)
        switch(operand)
        {
            case 0x00: .. case 0x07: // register
                return decodeRegisterOfOperand(operand);

            case 0x08: .. case 0x0f: // [register]
                return &mem[ *decodeRegisterOfOperand(operand & 7) ];

            case 0x10: .. case 0x17: // [register + next word]
                cost++;
                return &mem[ *decodeRegisterOfOperand(operand & 7) + mem[regs.pc++] ];

            case 0x18: // PUSH / POP
                return isA ? &mem[sp++] : &mem[--sp];

            case 0x19: // PEEK
                return &mem[sp];

            case 0x1a: // PICK n
                cost++;
                return &mem[ sp + mem[pc+1] ];

            case 0x1b:
                return &sp;

            case 0x1c:
                return &pc;

            case 0x1d:
                return &ex;

            case 0x1e: // [next word]
                cost++;
                return &mem[ mem[pc++] ];

            case 0x1f: // next word (literal)
                cost++;
                return &mem[pc++];

            default: // literal values
                assert(isA, "Bigger than 5 bit b operand");
                operand -= 0x21;
                return &operand;
        }
    }

    void addInterruptOrBurnOut(ushort intMsg)
    {
        isBurning = intQueue.addInterruptOrBurnOut(intMsg);

        if(isBurning)
            throw new Dcpu16Exception("CPU is burning!", computer, __FILE__, __LINE__);
    }

    version(CPUDebuggingMethods)
    {
        size_t[ushort] breakpoints; // TODO: private

        void setBreakpoint(ushort addr, size_t skipBeforeTriggering)
        {
            breakpoints[addr] = skipBeforeTriggering;
        }

        private bool testBreakpoint(ushort pc)
        {
            if(pc in breakpoints)
            {
                if(breakpoints[pc] > 0)
                    breakpoints[pc]--;
                else
                    return true;
            }

            return false;
        }
    }

    string regsToString() const pure
    {
        import std.string;

        with(regs)
        {
            enum fmt = "A:%04x  B:%04x  C:%04x  X:%04x  Y:%04x  Z:%04x  I:%04x  J:%04x  SP:%04x  PC:%04x  EX:%04x  IA:%04x iPC:%04x\n [%04x]  [%04x]  [%04x]  [%04x]  [%04x]  [%04x]  [%04x]  [%04x]   [%04x]   [%04x]   [%04x]   [%04x]   [%04x]";

            string res = format!fmt
                (
                    A, B, c, x, y, z, i, j, sp, PC, ex, ia, pc,
                    mem[A], mem[B], mem[c], mem[x], mem[y], mem[z],
                    mem[i], mem[j], mem[sp], mem[PC], mem[ex], mem[ia], mem[pc]
                );

            version(CPUDebuggingMethods)
            {
                res ~= format("\nDebug status: %04x", ds);
            }

            return res;
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
    ushort[] queue; //TODO: It should be replaced by a more faster mechanism
    bool isTriggeringEnabled = true;

    bool addInterruptOrBurnOut(ushort msg) pure
    {
        if(queue.length > 256)
            return true;

        queue ~= msg;

        return false;
    }

    bool empty() const pure
    {
        return queue.length == 0;
    }

    ushort pop() pure
    {
        auto ret = queue[0];
        queue = queue[1 .. $];

        return ret;
    }

    void reset() pure
    {
        queue.length = 0;
        isTriggeringEnabled = true;
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

private immutable byte[] opcodesCyclesCost =
[
    -1, // erroneous cost for special instruction
    1, // SET
    2, 2, 2, 2, // addition and multiplication
    3, 3, 3, 3, // division
    1, 1, 1, 1, 1, 1, // bit manipulation
    2, 2, 2, 2, 2, 2, 2, 2, // conditional branching
    -1, -1, // unused
    3, 3, // ADX and SBX
    -1, -1, // unused
    2,  2, // STI and STD
];

static assert(opcodesCyclesCost.length == Opcode.STD + 1);

private immutable byte[] specialOpcodesCyclesCost =
[
    -1, // reserved opcode
    3, // JSR
    -1, -1, -1, -1, -1, -1, // unused
    4, 1, 1, 3, 2, // interrupts
    -1, -1, -1, // unused
    2, 4, 4, // hardware
];

static assert(specialOpcodesCyclesCost.length == SpecialOpcode.HWI + 1);

struct Instruction
{
    union
    {
        ushort word;

        mixin(bitfields!(
            Opcode, "__opcode", 5,
            ubyte, "b",         5,
            ubyte, "a",         6,
        ));
    }

    bool isSpecialOpcode() const pure
    {
        return __opcode == Opcode.special;
    }

    Opcode basic_opcode() const pure
    {
        assert(!isSpecialOpcode);

        return __opcode;
    }

    SpecialOpcode spec_opcode() const pure
    {
        assert(isSpecialOpcode);

        return cast(SpecialOpcode) b;
    }

    string toString() const pure
    {
        import std.conv: to;

        if(isSpecialOpcode)
        {
            return
                format!"special opcode=%02x (%s), opA=%02x"
                (spec_opcode, spec_opcode.to!string, a);
        }
        else
        {
            return
                format!"opcode=%02x (%s), opA=%02x, opB=%02x"
                (basic_opcode, basic_opcode.to!string, a, b);
        }
    }
}

pure unittest
{
    auto comp = new Computer;
    auto cpu = CPU(comp);
    cpu.regs.x = 123;
    comp.mem[123] = 456;

    ushort b1 = 0x03;
    ushort b2 = 0x0b;
    assert(*cpu.decodeOperand(b1, false) == 123, "1");
    assert(*cpu.decodeOperand(b2, false) == 456, "2");

    // literal values:
    ushort a1 = 0x20;
    ushort a2 = 0x3f;
    assert(*cpu.decodeOperand(a1, true) == cast(ushort) -1);
    assert(*cpu.decodeOperand(a2, true) == 30);
}
