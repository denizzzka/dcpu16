module dcpu16.emulator.idevice;

interface IDevice
{
    uint id() const pure;
    ushort ver() const pure;
    uint manufacturer() const pure;
}
