module dcpu16.emulator.exception;

import std.exception;
import std.string;
import dcpu16.emulator.cpu: Instruction;
import dcpu16.emulator: Computer;

class Dcpu16Exception : Exception
{
    this(
        string msg,
        Computer comp,
        string file,
        size_t line
    ) pure
    {
        import dcpu16.asm_.decode;

        string insExpl = explainInstruction(comp.mem, comp.cpu.regs.PC, comp.cpu.getCurrInstruction);

        super(
            format(
                    "%s\nInstruction: %s\nDisassembled: %s\n%s",
                    msg,
                    comp.cpu.getCurrInstruction.toString,
                    insExpl,
                    comp.cpu.regsToString
                ),
            file,
            line
        );
    }
}
