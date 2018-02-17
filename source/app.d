import dlangui;
import dlangui.dialogs.filedlg;
import dlangui.dialogs.dialog;

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
                GroupBox { id: EMUL_SCREEN_GRP }
                VerticalLayout {
                    TextWidget { id: SPEED_INDICATOR; text: "<speed>"; fontSize: 100%; fontWeight: 800 }
                    TextWidget { id: CLOCK_NUM_INDICATOR; text: "0"; fontSize: 100%; fontWeight: 800 }
                    SliderWidget { id: CPU_SPEED }
                }
            }

            HorizontalLayout {
                Button { id: STATE; text: "Print state" }
                Button { id: STEP; text: "Step" }
                Button { id: PAUSE; text: "Run" }
                Button { id: RESET_CPU; text: "Reset CPU" }
                Button { id: LOAD_FILE; text: "Load dump..." }
            }
        }
    });

    Widget widget(dstring name)() const
    {
        static Widget w;

        if(w is null)
            w = window.mainWidget.childById(name);

        return w;
    }

    import dcpu16.emulator.devices.lem1802;
    import dcpu16.emulator.devices.keyboard;
    import std.stdio;

    auto comp = new Computer;
    auto disp = new LEM1802(comp);
    auto kbd = new Keyboard((ubyte){ return false; });
    comp.attachDevice = disp;
    comp.attachDevice = kbd;

    long clockingCounter;

    void onStepDg()
    {
        clockingCounter++;
        widget!"CLOCK_NUM_INDICATOR".text = clockingCounter.to!dstring;
    }

    auto emulScr = new EmulatorScreenWidget("EMUL_SCREEN_0", comp, disp, &onStepDg);
    window.mainWidget.childById("EMUL_SCREEN_GRP").addChild = emulScr;

    window.mainWidget.childById("PAUSE").addOnClickListener((Widget w) {
            emulScr.isPaused = !emulScr.isPaused;
            w.text = emulScr.isPaused ? "Run" : "Pause";
            return true;
        });

    window.mainWidget.childById("STEP").addOnClickListener((Widget) {
            emulScr.comp.cpu.step;
            comp.machineState.writeln;
            return true;
        });

    window.mainWidget.childById("STATE").addOnClickListener((Widget) {
            comp.machineState.writeln;
            return true;
        });

    window.mainWidget.childById("RESET_CPU").addOnClickListener((Widget) {
            emulScr.comp.cpu.reset;
            comp.machineState.writeln;
            return true;
        });

    auto sldr = cast(SliderWidget) window.mainWidget.childById("CPU_SPEED");
    sldr.minValue = 1;
    sldr.maxValue = 1001;
    sldr.position = 100;

    void displayCPUSpeed()
    {
        widget!"SPEED_INDICATOR".text = sldr.position.to!dstring~" Hz";
    }

    displayCPUSpeed;

    sldr.scrollEvent = delegate(AbstractSlider source, ScrollEvent event) {
            if (event.action == ScrollAction.SliderMoved)
            {
                displayCPUSpeed;
                emulScr.setCPUFreq(source.position);
            }

            return true;
        };

    window.mainWidget.childById("LOAD_FILE").addOnClickListener((Widget) {
            UIString caption;
            caption = "FILEDLG"d;
            FileDialog dlg = new FileDialog(caption, window);
            string filename;

            dlg.dialogResult = delegate(Dialog dlg, const Action result)
            {
                if (result.id == ACTION_OPEN.id)
                {
                    filename = result.stringParam;
                    emulScr.loadBinaryFile(filename, true); // FIXME: endiannes selection
                }
            };

            dlg.show();

            return true;
        });

    immutable ushort[] scrFill =
    [
        0x7c01, 0xf000, 0x7c21, 0x8000, 0x0121, 0x8802, 0x8822, 0x7c32,
        0x8180, 0x7f81, 0x000d, 0x7f81, 0x0004, 0x7f81, 0x000d
    ];

    if(args.length <= 1)
        comp.load(scrFill);
    else
        emulScr.loadBinaryFile(args[1], true);

    emulScr.startClocking(sldr.position);

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
    private ulong blinkingTimer;
    private void delegate() onStepDg;

    this(string id, Computer c, LEM1802 d, void delegate() onStep)
    {
        super(id);

        cdbuf = new ColorDrawBuf(X_PIXELS, Y_PIXELS);
        comp = c;
        display = d;
        onStepDg = onStep;
    }

    void setCPUFreq(uint Hz)
    {
        assert(Hz > 0);
        assert(Hz <= 1000);

        auto mills = 1000 / Hz;
        static bool timerCreated = false;

        if(!timerCreated)
            timerCreated = true;
        else
            cancelTimer(clockTimer);

        clockTimer = setTimer(mills);
    }

    void startClocking(uint initialClockingFreq_Hz)
    {
        setCPUFreq(initialClockingFreq_Hz);
        screenDrawTimer = setTimer(1000);
        blinkingTimer = setTimer(800);
    }

    void step()
    {
        if(!isPaused)
        {
            import dcpu16.emulator.exception;

            onStepDg();

            try
            {
                comp.cpu.step;
            }
            catch(Dcpu16Exception e)
            {
                import std.stdio;

                e.msg.writeln;
                isPaused = true;
            }
        }
    }

    override bool onTimer(ulong id)
    {
        if(id == clockTimer)
        {
            step();
        }
        else if(id == screenDrawTimer)
        {
            import dlangui.platforms.sdl.sdlapp;

            //~ invalidate();
            //~ (cast(SDLWindow)window).redraw();
        }
        else if(id == blinkingTimer)
        {
            display.switchBlink();
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

    void loadBinaryFile(string filename, bool wrongEndianness)
    {
        import std.file;

        ubyte[] blob = cast(ubyte[]) read(filename);
        comp.load(blob, wrongEndianness);
    }
}
