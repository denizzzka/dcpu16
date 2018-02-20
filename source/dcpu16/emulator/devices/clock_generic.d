module dcpu16.emulator.devices.clock;

import dcpu16.emulator.idevice;
import dcpu16.emulator;

class Clock : IDevice
{
    override uint id() const pure { return 0x12d0b402; };
    override uint manufacturer() const pure { return 0x1c6c8b36; };
    override ushort ver() const pure { return 2; };

    private Computer comp;
    private ushort ticks;
    private ushort timer;
    private ushort timerInterval; // Means 60/n ticks per second
    private ushort interruptMsg;

    this(Computer c)
    {
        comp = c;
    }

    override void reset()
    {
        ticks = 0;
        timer = 0;
        timerInterval = 0;
        interruptMsg = 0;
    }

    override void handleHardwareInterrupt(Computer _comp)
    {
        assert(comp == _comp);

        with(InterruptActions)
        with(comp)
        with(cpu.regs)
        switch(A)
        {
            case SET_SPEED:
                timerInterval = B;
                break;

            case GET_TICKS:
                c = ticks;
                ticks = 0;
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
        if(timerInterval != 0)
        {
            timer++;

            if(timer >= 60 / timerInterval)
            {
                timer = 0;
                ticks++;

                if(interruptMsg)
                    comp.cpu.addInterruptOrBurnOut(interruptMsg);
            }
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

unittest
{
    enum str = import("tester_clock.bin");
    auto blob = cast(ubyte[]) str;

    auto comp = new Computer();
    auto clock = new Clock(comp);
    comp.devices ~= clock;

    comp.load(blob, true);

    size_t cnt;
    ushort prev;

    foreach(i; 0 .. 1_000_000) // 10 seconds on 1 kHz
    {
        comp.cpu.step();

        if(i % (100_000 / 60) == 0)
            clock.clock60Hz();

        if(comp.cpu.regs.j != prev)
        {
            prev = comp.cpu.regs.j;
            cnt++;
        }
    }

    assert(cnt == 600); // 60 cycles * 10 seconds
}
