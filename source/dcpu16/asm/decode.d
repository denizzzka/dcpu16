module dcpu16.emulator.asm_.decode;

import dcpu16.emulator: Memory;
import dcpu16.emulator.cpu;

pure:

private string explainRegisterOfOperand(ushort operand)
{
    switch(operand)
    {
        case 0: return "A";
        case 1: return "B";
        case 2: return "C";
        case 3: return "X";
        case 4: return "Y";
        case 5: return "Z";
        case 6: return "I";
        case 7: return "J";
        default: assert(false);
    }
}

private string explainOperand(in Memory mem, ref ushort pc, ushort operand, bool isA) pure
{
    if(operand > 0x3f)
        throw new Exception("Unknown operand "~operand.fmt, __FILE__, __LINE__);

    switch(operand)
    {
        case 0x00: .. case 0x07: // register
            return explainRegisterOfOperand(operand);

        case 0x08: .. case 0x0f: // [register]
            return "["~explainRegisterOfOperand(operand)~"]";

        case 0x10: .. case 0x17: // [register + next word]
            return "["~explainRegisterOfOperand(operand & 7)~" + "~mem[pc+1].fmt~"]";

        case 0x18:
            return isA ? "PUSH" : "POP";

        case 0x19:
            return "PEEK";

        case 0x1a: // PICK n
            return "PICK "~mem[pc+1].fmt;

        case 0x1b:
            return "SP";

        case 0x1c:
            return "PC";

        case 0x1d:
            return "EX";

        case 0x1e: // [next word]
            return "["~mem[pc++].fmt~"]";

        case 0x1f: // next word (literal)
            return mem[pc++].fmt;

        default: // literal values
            assert(isA, "Bigger than 5 bit b operand");
            operand -= 0x21;
            return operand.fmt;
    }
}

private void complainWrongOpcode(in Instruction ins) pure
{
    throw new Exception("Wrong opcode, instruction "~ins.toString, __FILE__, __LINE__);
}

import std.string: format;

string explainBasicInstruction(in Memory mem, ushort pc, in Instruction ins)
{
    if(ins.opcode > Opcode.STD)
        complainWrongOpcode(ins);

    with(Opcode)
    switch(ins.opcode)
    {
        case special: assert(false);
        case unused_0x18:
        case unused_0x19:
        case unused_0x1c:
        case unused_0x1d:
            complainWrongOpcode(ins);
            assert(false);

        default:
            break;
    }

    string a = explainOperand(mem, pc, ins.a, true);
    string b = explainOperand(mem, pc, ins.b, false);

    import std.conv: to;

    return format("%s %s, %s", ins.opcode.to!string, a, b);
}

private string fmt(T)(T v)
{
    return format("%04x", v);
}
