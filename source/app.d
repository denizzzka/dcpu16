import dlangui;
import dlangui.dialogs.filedlg;
import dlangui.dialogs.dialog;

mixin APP_ENTRY_POINT;

import dcpu16.emulator;
import dcpu16.emulator.devices.lem1802;
import dcpu16.emulator.devices.keyboard;
import dcpu16.emulator.exception: Dcpu16Exception;

import std.stdio;
import std.format;

extern (C) int UIAppMain(string[] args)
{
    Window window = Platform.instance.createWindow("DCPU-16 emulator", null, WindowFlag.Resizable | WindowFlag.ExpandSize);
    window.windowOrContentResizeMode = WindowOrContentResizeMode.resizeWindow;

    window.mainWidget = parseML(q{
        VerticalLayout
        {
            TextWidget { text: "DCPU-16 emulator"; fontSize: 150%; fontWeight: 800 }

            HorizontalLayout {
                GroupBox { id: EMUL_SCREEN_GRP; text: "Screen" }
                VerticalLayout {
                    TextWidget { id: SPEED_INDICATOR; text: "<speed>"; fontSize: 100%; fontWeight: 800 }
                    TextWidget { id: CLOCK_NUM_INDICATOR; text: "0"; fontSize: 100%; fontWeight: 800 }
                    SliderWidget { id: CPU_SPEED; minWidth: 200 }
                    StringGridWidget { id: MEM_DUMP; minWidth: 300; minHeight: 600;  }
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

    T widget(dstring name, T = Widget)() const
    {
        static T w;

        if(w is null)
            w = cast(T) window.mainWidget.childById(name);

        return w;
    }

    auto comp = new Computer;
    auto disp = new LEM1802(comp);
    auto kbd = new Keyboard(comp, (ubyte){ return false; });
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
    emulScr.keyboard = kbd;

    widget!("MEM_DUMP", StringGridWidget).resize(4, cast(int) emulScr.comp.mem.length / 4);
    foreach(i; 0 .. 4)
        widget!("MEM_DUMP", StringGridWidget).setColTitle(i, i.to!dstring);

    foreach(int i; 0 .. cast(int) emulScr.comp.mem.length / 4)
        widget!("MEM_DUMP", StringGridWidget).setRowTitle(i, format!dchar("%#06x", i*4));

    disp.onInterruptAction = &emulScr.remapVideo;

    void displayPauseState()
    {
        widget!"PAUSE".text = emulScr.isPaused ? "Run" : "Pause";
        widget!"STEP".enabled = emulScr.isPaused;

        const m = comp.mem;
        foreach(int row; 0 .. cast(int) m.length / 4)
            foreach(int col; 0 .. 4)
                widget!("MEM_DUMP", StringGridWidget).setCellText(col, row, format!dchar("%#06x", m[row * 4 + col]));
    }

    displayPauseState;

    widget!"PAUSE".addOnClickListener((Widget w) {
            emulScr.isPaused = !emulScr.isPaused;
            displayPauseState;
            return true;
        });

    emulScr.onExceptionDg = (Dcpu16Exception e)
    {
        import std.stdio;
        e.msg.writeln;

        if(!emulScr.isPaused)
        {
            emulScr.isPaused = true;
            displayPauseState;
        }
    };

    window.mainWidget.childById("STEP").addOnClickListener((Widget) {
            emulScr.step;
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
    sldr.maxValue = 100_001;
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

    displayPauseState;

    emulScr.startClocking(sldr.position);

    // show window
    window.show();

    // run message loop
    return Platform.instance.enterMessageLoop();
}

class EmulatorScreenWidget : ImageWidget
{
    enum borderWidth = 4;
    private ColorDrawBuf cdbuf;
    private Computer comp;
    private LEM1802 display;
    Keyboard keyboard;
    bool isPaused = true;

    private ulong clockTimer;
    private ulong screenDrawTimer;
    private ulong blinkingTimer;
    private void delegate() onStepDg;
    private void delegate(Dcpu16Exception) onExceptionDg;
    private ColorDrawBuf[128] font;
    private ColorDrawBuf bgGlyph;

    this(string id, Computer c, LEM1802 d, void delegate() onStep)
    {
        super(id);

        cdbuf = new ColorDrawBuf(X_PIXELS + borderWidth*2, Y_PIXELS + borderWidth*2);
        comp = c;
        display = d;
        onStepDg = onStep;
        bgGlyph = new ColorDrawBuf(CHAR_SIZE_X, CHAR_SIZE_Y);

        foreach(ref sym; font)
        {
            sym = new ColorDrawBuf(CHAR_SIZE_X, CHAR_SIZE_Y);
            sym.fill(0xff00ff00);
        }

        loadFontBitmap;
    }

    private uint numOfStepsPerTick;

    void setCPUFreq(uint Hz)
    {
        assert(Hz > 0);

        enum minTimerInterval = 50;
        uint timerInterval;

        if(1000 / Hz > minTimerInterval)
        {
            timerInterval = 1000 / Hz;
            numOfStepsPerTick = 1;
        }
        else
        {
            timerInterval = minTimerInterval;
            numOfStepsPerTick = Hz / timerInterval;
        }

        static bool timerCreated = false;

        if(!timerCreated)
            timerCreated = true;
        else
            cancelTimer(clockTimer);

        clockTimer = setTimer(timerInterval);
    }

    void startClocking(uint initialClockingFreq_Hz)
    {
        setCPUFreq(initialClockingFreq_Hz);
        screenDrawTimer = setTimer(1000);
        blinkingTimer = setTimer(800);
    }

    void tick()
    {
        try
        {
            foreach(_; 0 .. numOfStepsPerTick)
                step;
        }
        catch(Dcpu16Exception e)
        {
            if(onExceptionDg)
                onExceptionDg(e);
        }
    }

    void step()
    {
        import dcpu16.emulator.exception;

        onStepDg();

        comp.cpu.step;
    }

    override bool onTimer(ulong id)
    {
        if(id == clockTimer)
        {
            if(!isPaused)
                tick();
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

    private static uint makeRGBA(PaletteColor c) pure @property
    {
        import col = dlangui.graphics.colors;

        return col.makeRGBA(
                c.r * 17,
                c.g * 17,
                c.b * 17,
                0
            );
    }

    private void placeFrameToBuf()
    {
        // Border
        cdbuf.fillRect(Rect(0, 0, cdbuf.width, cdbuf.height), makeRGBA(display.getBorderColor));

        foreach(ubyte y; 0 .. Y_RESOLUTION)
            foreach(ubyte x; 0 .. X_RESOLUTION)
            {
                Symbol sym = display.getSymbol(x, y);
                bool visibility = !sym.blinking || display.isBlinkingVisible;
                auto bg = makeRGBA(display.getColor(sym.background));

                bgGlyph.fill(bg);

                if(sym.foreground != sym.background && visibility)
                {
                    auto fg = makeRGBA(display.getColor(sym.foreground));

                    ColorTransform tr = { multiply: fg | 0xff000000 };
                    auto fgGlyph = font[sym.character].transformColors(tr);

                    bgGlyph.drawImage(0, 0, fgGlyph);
                }

                cdbuf.drawImage(x * CHAR_SIZE_X + borderWidth, y * CHAR_SIZE_Y + borderWidth, bgGlyph);
            }
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

    private void loadFontBitmap()
    {
        foreach(ubyte i, ref sym; font)
        {
            LEM1802.SymbolBitmap b = display.getSymbolBitmap(i);

            foreach(y; 0 .. CHAR_SIZE_Y)
            {
                foreach(x; 0 .. CHAR_SIZE_X)
                {
                    bool isSet = display.getPixelOfSymbol(b, x, y);

                    if(isSet)
                        sym.drawPixel(x, y, 0x00ffffff);
                }
            }
        }
    }

    void remapVideo(InterruptAction ia)
    {
        if(ia == InterruptAction.MEM_MAP_FONT)
            loadFontBitmap;
    }

    override bool wantsKeyTracking() { return true; }

    override bool onKeyEvent(KeyEvent e)
    {
        if(e.action == KeyAction.Text)
        {
            // Numbers and capital letters
            if(e.action >= 0x30 && e.action <= 0x5a)
            {
                keyboard.keyPressed(cast(ubyte) e.action);
            }

            import dlangui.core.logger;
            import std.conv;
            Log.d("================ key event"~e.to!string);
        }

        return true;
    }
}
