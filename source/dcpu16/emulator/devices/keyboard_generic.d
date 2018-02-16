module dcpu16.emulator.devices.keyboard;

import dcpu16.emulator.idevice;
import dcpu16.emulator;

class Keyboard : IDevice
{
    uint id() const pure { return 0x30cf7406; };
    uint manufacturer() const pure { return 0; };
    ushort ver() const pure { return 1; };

    private Computer comp;
    private ubyte[] buf;
    private ubyte readIdx;
    private ubyte writeIdx;
    private CheckKeyIsPressed checkKeyPressed;
    private bool enableMemMapping;

    alias CheckKeyIsPressed = bool delegate(ubyte ascii_or_enum_Key);

    this(CheckKeyIsPressed dg, bool enable0x9000Mapping = true, size_t keyBufferLength = 8)
    {
        enableMemMapping = enable0x9000Mapping;
        buf.length = keyBufferLength;
    }

    void handleHardwareInterrupt(Computer comp)
    {
        with(InterruptActions)
        with(comp)
        with(cpu.regs)
        switch(A)
        {
            case CLEAR_BUFFER:
                foreach(ref k; buf)
                    k = 0;

                return;

            case GET_NEXT:
                assert(false);

            case CHECK_KEY:
                ubyte b = comp.cpu.regs.B & ubyte.max;
                if(b != comp.cpu.regs.B) return;
                comp.cpu.regs.c = checkKeyPressed(b) ? 1 : 0;
                return;

            case SET_INT:
                assert(false);

            default:
                break;
        }
    }

    /// ASCII code or enum Key
    void keyPressed(ubyte ascii_or_enum_Key)
    {
        assert(ascii_or_enum_Key != 0);
        // TODO: add more checks

        // A 16-word buffer [0x9000 to 0x900e] holds the most recently input characters in a ring buffer, one word per character.
        if(enableMemMapping)
        {
            static ushort mapIdx = 0x9000;

            comp.mem[mapIdx] = ascii_or_enum_Key;
            mapIdx++;

            if(mapIdx > 0x900e)
                mapIdx = 0x9000;
        }
    }
}

unittest
{
    // 0x9010 holds end of buffer
    ushort[] createRingBuff= [
            0x7f01, 0x0000, 0x7f81, 0x0004, 0x7821, 0x9010, 0x4401, 0x9000,
            0x8621, 0x9000, 0x8822, 0xc428, 0x07c1, 0x9010, 0x6381
        ];

    auto comp = new Computer();
    comp.load(createRingBuff);

    foreach(_; 0 .. 4000)
    {
        //~ import std.stdio;
        //~ comp.machineState.writeln;
        //~ comp.memDump(0x9000).writeln;
        //~ comp.memDump(0x9010).writeln;
        comp.cpu.step;
    }
}

enum InterruptActions : ushort
{
    CLEAR_BUFFER,
    GET_NEXT,
    CHECK_KEY,
    SET_INT,
}

enum Key : ubyte
{
    none,
    Backspace = 0x10,
    Return,
    Insert,
    Delete,
    ArrowUp = 0x80,
    ArrowDown,
    ArrowLeft,
    ArrowRight,
    Shift = 0x90,
    Control,
    Alt, /// Unofficial
}