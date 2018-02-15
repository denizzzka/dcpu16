module dcpu16.emulator.devices.keyboard;

import dcpu16.emulator.idevice;

class Keyboard : IDevice
{
    uint id() const pure { return 0x30cf7406; };
    uint manufacturer() const pure { return 0; };
    ushort ver() const pure { return 1; };

    void handleHardwareInterrupt(Computer comp)
    {
        with(InterruptActions)
        with(comp)
        with(cpu.regs)
        switch(A)
        {
            case CLEAR_BUFFER:
                screen = (B == 0) ? null : &mem[B];
                return;

            default:
                break;
        }
    }
}

unittest
{
    // A 16-word buffer [0x9000 to 0x900e] holds the most recently input characters in a ring buffer, one word per character.
    // 0x9010 holds end of buffer
    ushort[] ringBuff= [
            0x7f01, 0x0000, 0x7f81, 0x0004, 0x7821, 0x9010, 0x4401, 0x9000,
            0x8621, 0x9000, 0x8822, 0xc428, 0x07c1, 0x9010, 0x6381
        ];
}

enum InterruptActions : ushort
{
    CLEAR_BUFFER,
    STORE_NEXT_KEY,
    IS_KEY_PRESSED,
    ENABLE_INTS,
}
