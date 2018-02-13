module dcpu16.emulator.devices.lem1802;

import dcpu16.emulator.idevice;
import dcpu16.emulator;

class LEM1802 : IDevice
{
    uint id() const pure { return 0x7349f615; };
    uint manufacturer() const pure { return 0x1c6c8b36; };
    ushort ver() const pure { return 0x1802 ; };

    void handleInterrupt(Computer comp)
    {
    }
}
