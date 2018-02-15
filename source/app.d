import dlangui;

mixin APP_ENTRY_POINT;

import dcpu16.emulator;

extern (C) int UIAppMain(string[] args)
{
    Window window = Platform.instance.createWindow("DCPU-16 emulator", null, WindowFlag.Resizable | WindowFlag.ExpandSize);
    window.windowOrContentResizeMode = WindowOrContentResizeMode.resizeWindow;

    window.mainWidget = parseML(q{
        VerticalLayout
        {
            TextWidget { text: "DCPU-16 emulator"; fontSize: 150%; fontWeight: 800 }

            HorizontalLayout {
                Button { id: STEP; text: "Step" }
                Button { id: PAUSE; text: "Pause" }
                Button { id: RESET_CPU; text: "Reset CPU" }
                Button { id: REDRAW; text: "Update videobuffer" }
            }
        }
    });


    import dcpu16.emulator.devices.lem1802;
    import std.stdio;

    auto comp = new Computer;
    auto disp = new LEM1802(comp);
    comp.attachDevice = disp;

    auto emulScr = new EmulatorScreenWidget("EMUL_SCREEN0", comp, disp);
    window.mainWidget.insertChild(emulScr, 1);

    window.mainWidget.childById("PAUSE").addOnClickListener((Widget) {
            emulScr.isPaused = !emulScr.isPaused;
            return true;
        });

    window.mainWidget.childById("STEP").addOnClickListener((Widget) {
            emulScr.comp.cpu.step;
            comp.machineState.writeln;
            return true;
        });

    window.mainWidget.childById("RESET_CPU").addOnClickListener((Widget) {
            emulScr.comp.cpu.reset;
            comp.machineState.writeln;
            return true;
        });

    window.mainWidget.childById("REDRAW").addOnClickListener((Widget) {
            emulScr.placeFrameToBuf;
            return true;
        });

    ushort[] scrFill =
    [
        0x7c01, 0xf000, 0x7c21, 0x8000, 0x0121, 0x8802, 0x8822, 0x7c32,
        0x8180, 0x7f81, 0x000d, 0x7f81, 0x0004, 0x7f81, 0x000d
    ];
    comp.load(scrFill);

    emulScr.startClocking();

    // show window
    window.show();

    // run message loop
    return Platform.instance.enterMessageLoop();
}

import dcpu16.emulator.devices.lem1802;

class EmulatorScreenWidget : ImageWidget
{
    public ColorDrawBuf cdbuf;
    private Computer comp;
    private LEM1802 display;
    bool isPaused = true;

    private ulong clockTimer;
    private ulong screenDrawTimer;

    this(string id, Computer c, LEM1802 d)
    {
        super(id);

        cdbuf = new ColorDrawBuf(X_PIXELS, Y_PIXELS);
        comp = c;
        display = d;
    }

    void startClocking()
    {
        clockTimer = setTimer(10);
        screenDrawTimer = setTimer(1000);
    }

    override bool onTimer(ulong id)
    {
        if(id == clockTimer)
        {
            import std.stdio;

            if(!isPaused)
            {
                comp.cpu.step;
                comp.machineState.writeln;
            }
        }
        else if(screenDrawTimer)
        {
            import dlangui.platforms.sdl.sdlapp;

            //~ invalidate();
            //~ (cast(SDLWindow)window).redraw();
        }

        return true;
    }

    private void placeFrameToBuf()
    {
        display.forEachPixel(
            (x, y, c)
            {
                auto rgba = makeRGBA(
                        c.r * 17,
                        c.g * 17,
                        c.b * 17,
                        0
                    );

                cdbuf.drawPixel(x, y, rgba);
            }
        );
    }

    override void onDraw(DrawBuf buf)
    {
        if(!visible)
            return;

        placeFrameToBuf();

        auto srcRect = Rect(0, 0, cdbuf.width, cdbuf.height);
        buf.drawRescaled(pos, cdbuf, srcRect);
    }

    override void measure(int parentWidth, int parentHeight)
    {
        measuredContent(parentWidth, parentHeight, 640, 480);
    }
}
