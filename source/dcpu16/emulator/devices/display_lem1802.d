module dcpu16.emulator.devices.lem1802;

import dcpu16.emulator.idevice;
import dcpu16.emulator;

class LEM1802 : IDevice
{
    uint id() const pure { return 0x7349f615; };
    uint manufacturer() const pure { return 0x1c6c8b36; };
    ushort ver() const pure { return 0x1802 ; };

    private ushort* screen;
    private ushort* font;
    private ushort* palette;
    private ubyte borderColor;

    void handleHardwareInterrupt(Computer comp)
    {
        with(comp)
        with(cpu.regs)
        switch(A)
        {
            case 0:
                screen = &mem[B];
                return;

            case 1:
                font = &mem[B];
                return;

            case 2:
                palette = &mem[B];
                return;

            case 3:
                borderColor = B & 0xF;
                return;

            default:
                break;
        }
    }
}
