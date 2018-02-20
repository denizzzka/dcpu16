module dcpu16.emulator.devices.clock;

import dcpu16.emulator.idevice;
import dcpu16.emulator;

class Clock : IDevice
{
    uint id() const pure { return 0x12d1b402; };
    uint manufacturer() const pure { return 0x1c6c8b36; };
    ushort ver() const pure { return 2; };

    void reset(){}

    void handleHardwareInterrupt(in Computer comp)
    {
        with(InterruptActions)
        with(comp)
        with(cpu.regs)
        switch(A)
        {
            case SET_SPEED:
                assert(false);

            case GET_TICKS:
                assert(false);

            default:
                assert(false);
        }
    }
}

enum InterruptActions : ushort
{
    SET_SPEED,
    GET_TICKS,
    SET_INT,
    REAL_TIME = 0x10,
    RUN_TIME,
    SET_REAL_TIME,
    RESET = 0xffff
}
