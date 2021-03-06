module dcpu16.emulator.idevice;

import dcpu16.emulator: Computer;

abstract class /*interface*/ IDevice
{
    uint id() const pure;
    ushort ver() const pure;
    uint manufacturer() const pure;
    void handleHardwareInterrupt(Computer);
    void reset();
}
