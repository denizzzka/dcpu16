module dcpu16.emulator.idevice;

interface IDevice
{
    uint id() const;
    ushort ver() const;
    uint manufacturer() const;
}
