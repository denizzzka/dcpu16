import dlangui;

mixin APP_ENTRY_POINT;

extern (C) int UIAppMain(string[] args)
{
    Window window = Platform.instance.createWindow("DCPU-16 emulator", null);

    window.mainWidget = parseML(q{
        VerticalLayout
        {
            TextWidget { text: "Hello World example for DlangUI"; fontSize: 150%; fontWeight: 800 }

            ImageWidget {  }

            HorizontalLayout {
                Button { id: btnOk; text: "Ok" }
                Button { id: btnCancel; text: "Cancel" }
            }
        }
    });

    import dcpu16.emulator;
    import dcpu16.emulator.devices.lem1802;

    auto comp = new Computer;
    auto disp = new LEM1802(comp);
    comp.attachDevice = disp;

    enum blob = import("test.bin");
    comp.load(cast(ubyte[]) blob);

    foreach(_; 0 .. 4000)
    {
        import std.stdio;
        comp.machineState.writeln;
        comp.cpu.step;
    }

    import dlangui.graphics.images;

    uint[PIXELS_NUM] frame;
    size_t idx;
    disp.forEachPixel(
        (PaletteColor c)
        {
            frame[idx] = makeRGBA(
                    c.r * 17,
                    c.g * 17,
                    c.b * 17,
                    0
                );
            idx++;
        }
    );

    // show window
    window.show();

    // run message loop
    return Platform.instance.enterMessageLoop();
}
