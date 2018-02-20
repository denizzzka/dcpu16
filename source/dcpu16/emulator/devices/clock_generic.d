module dcpu16.emulator.devices.clock;

import dcpu16.emulator.idevice;
import dcpu16.emulator;

class Clock : IDevice
{
    uint id() const pure { return 0x12d1b402; };
    uint manufacturer() const pure { return 0x1c6c8b36; };
    ushort ver() const pure { return 2; };

    private Computer comp;
    private ushort clock;
    private ushort timer;
    private ushort timerInterval; // Means 60/n ticks per second
    private ushort interruptMsg;

    this(Computer c)
    {
        comp = c;
    }

    void reset()
    {
        clock = 0;
        timer = 0;
        timerInterval = 0;
        interruptMsg = 0;
    }

    void handleHardwareInterrupt(Computer comp)
    {
        with(InterruptActions)
        with(comp)
        with(cpu.regs)
        switch(A)
        {
            case SET_SPEED:
                timerInterval = B;
                break;

            case GET_TICKS:
                c = timerInterval ? clock / timerInterval : 0;
                clock %= timerInterval;
                break;

            case SET_INT:
                interruptMsg = B;
                break;

            default:
                assert(false);
        }
    }

    void clock60Hz()
    {
        clock++;
        timer++;

        if(interruptMsg && timerInterval)
            if(timer / timerInterval)
            {
                timer = 0;

                comp.cpu.addInterruptOrBurnOut(interruptMsg);
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
