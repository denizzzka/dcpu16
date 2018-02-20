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
            HorizontalLayout {
                VerticalLayout {
                    GroupBox { id: EMUL_SCREEN_GRP; text: "Screen" }
                    GroupBox { text: "Breakpoints";
                        EditBox { id: BREAKPOINTS; minHeight: 100 }
                    }
                }
                VerticalLayout {
                    HorizontalLayout {
                        GroupBox {
                            text: "Step counter";
                            TextWidget { id: STEP_NUM_INDICATOR; text: "0"; fontSize: 100%; fontWeight: 800 }
                        }
                        GroupBox {
                            text: "Clock counter";
                            TextWidget { id: CLOCK_NUM_INDICATOR; text: "0"; fontSize: 100%; fontWeight: 800 }
                        }
                    }
                    GroupBox {
                        text: "Frequency";
                        TextWidget { id: SPEED_INDICATOR; text: "<speed>"; fontSize: 100%; fontWeight: 800 }
                        SliderWidget { id: CPU_SPEED; minWidth: 200 }
                    }
                    GroupBox {
                        text: "Memory";
                        StringGridWidget { id: MEM_DUMP; minWidth: 240; minHeight: 450 }
                    }
                }
            }

            HorizontalLayout {
                Button { id: STATE; text: "Print state" }
                Button { id: STEP; text: "Step" }
                Button { id: PAUSE; text: "Run" }
                Button { id: RESET_CPU; text: "Reset CPU" }
                Button { id: RESET_COMP; text: "Reset computer" }
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

    auto emulScr = new EmulatorScreenWidget("EMUL_SCREEN_0", comp, disp);
    window.mainWidget.childById("EMUL_SCREEN_GRP").addChild = emulScr;
    emulScr.keyboard = kbd;

    enum memDumpColNum = 4;

    widget!("MEM_DUMP", StringGridWidget).resize(memDumpColNum, cast(int) emulScr.comp.mem.length / memDumpColNum);
    widget!("MEM_DUMP", StringGridWidget).showColHeaders = false;

    foreach(int i; 0 .. cast(int) emulScr.comp.mem.length / memDumpColNum)
        widget!("MEM_DUMP", StringGridWidget).setRowTitle(i, format!dchar("%#06x", i * memDumpColNum));

    void refreshMemDump()
    {
        const m = comp.mem;
        foreach(int row; 0 .. cast(int) m.length / memDumpColNum)
            foreach(int col; 0 .. memDumpColNum)
                widget!("MEM_DUMP", StringGridWidget).setCellText(col, row, format!dchar("%04x", m[row * memDumpColNum + col]));
    }

    refreshMemDump;
    widget!("MEM_DUMP", StringGridWidget).autoFit;

    void displayPauseState()
    {
        widget!"PAUSE".text = emulScr.paused ? "Run" : "Pause";
        widget!"STEP".enabled = emulScr.paused;
        widget!"MEM_DUMP".visibility = emulScr.paused ? Visibility.Visible : Visibility.Invisible;

        if(emulScr.paused) refreshMemDump;
    }

    displayPauseState;
    emulScr.onPauseStateChanged = &displayPauseState;

    void refreshClock()
    {
        widget!"STEP_NUM_INDICATOR".text = emulScr.stepCounter.to!dstring;
        widget!"CLOCK_NUM_INDICATOR".text = emulScr.clockCounter.to!dstring;
    }

    refreshClock;
    emulScr.onScreenDraw = &refreshClock;

    widget!"PAUSE".addOnClickListener((Widget w) {
            emulScr.paused = !emulScr.paused;
            return true;
        });

    emulScr.onExceptionDg = (Dcpu16Exception e)
    {
        import std.stdio;
        e.msg.writeln;
    };

    window.mainWidget.childById("STEP").addOnClickListener((Widget) {
            emulScr.clockCounter += emulScr.step(); // FIXME: check for exceptions is need here
            refreshClock;
            refreshMemDump;
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

    window.mainWidget.childById("RESET_COMP").addOnClickListener((Widget) {
            emulScr.reset;
            return true;
        });

    auto sldr = cast(SliderWidget) window.mainWidget.childById("CPU_SPEED");
    sldr.minValue = 1;
    sldr.maxValue = 200_001;
    sldr.position = emulScr.freqHz;

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

    class NumericEditableContent : EditableContentChangeListener
    {
        void onEditableContentChanged(EditableContent c)
        {
            emulScr.comp.cpu.breakpoints.clear;

            for(auto i = 0; i < c.length; i++)
            {
                import std.string;
                import std.conv;

                try
                    emulScr.comp.cpu.setBreakpoint(c[i].chomp.to!ushort, 0);
                catch(ConvException)
                {}
            }
        }
    }

    widget!("BREAKPOINTS", EditBox).contentChange = new NumericEditableContent;


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

    refreshMemDump;

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
    long stepCounter;
    long clockCounter;
    void delegate() onPauseStateChanged;

    private bool _paused = true;
    private void delegate() onScreenDraw;
    private void delegate(Dcpu16Exception) onExceptionDg;

    this(string id, Computer c, LEM1802 d)
    {
        super(id);

        {
            cdbuf = new ColorDrawBuf(X_PIXELS + borderWidth*2, Y_PIXELS + borderWidth*2);
            DrawBufRef b = cdbuf;
            drawable = new ImageDrawable(b); // just for do not leaving it empty
        }

        comp = c;
        display = d;
    }

    void reset()
    {
        clockCounter = 0;
        stepCounter = 0;
        comp.reset();
        paused = true;
    }

    bool paused() const { return _paused; }
    void paused(bool state)
    {
        _paused = state;

        if(onPauseStateChanged) onPauseStateChanged();
    }

    private uint freqHz = 100_000;

    void setCPUFreq(uint Hz)
    {
        assert(Hz > 0);

        freqHz = Hz;
    }

    void tick()
    {
        static ubyte cyclesRemaining;

        try
        {
            if(cyclesRemaining == 0)
            {
                cyclesRemaining = step();

                if(comp.cpu.regs.ds != 0) // breakpoint check
                {
                    paused = true;
                    comp.machineState.writeln;
                    comp.cpu.regs.ds = 0;
                }
            }

            cyclesRemaining--;
            clockCounter++;
        }
        catch(Dcpu16Exception e)
        {
            cyclesRemaining = 0;
            paused = true;

            if(onExceptionDg)
                onExceptionDg(e);
        }
    }

    ubyte step()
    {
        import dcpu16.emulator.exception;

        scope(success) stepCounter++;

        return comp.cpu.step();
    }

    override bool animating() { return true; }

    /// animates window; interval is time left from previous draw, in hnsecs (1/10000000 of second)
    override void animate(long interval)
    {
        enum blinkPeriod = 8_000_000; // 0.8 sec

        static ulong blinkingTime;
        blinkingTime += interval;

        if(blinkingTime > blinkPeriod)
        {
            blinkingTime %= blinkPeriod;
            display.switchBlink();
        }

        static ulong clockInterval;
        clockInterval += interval;

        auto period = 10_000_000 / freqHz;
        auto ticks = clockInterval / period;
        clockInterval %= period;

        foreach(_; 0 .. ticks)
            if(!paused)
                tick();

        display.splashClock(interval);
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
        // Recreation is need: OpenGL can't draw it after first drawing because caching
        cdbuf = new ColorDrawBuf(X_PIXELS + borderWidth*2, Y_PIXELS + borderWidth*2);
        cdbuf.fill(makeRGBA(display.getBorderColor));

        if(display.isSplashDisplayed)
        {
            placeSplashToBuf;
            return;
        }

        foreach(ubyte y; 0 .. Y_RESOLUTION)
            foreach(ubyte x; 0 .. X_RESOLUTION)
            {
                Symbol sym = display.getSymbol(x, y);
                bool visibility = !sym.blinking || display.isBlinkingVisible;
                auto bg = makeRGBA(display.getColor(sym.background));

                auto bgGlyph = new ColorDrawBuf(CHAR_SIZE_X, CHAR_SIZE_Y);
                bgGlyph.fill(bg);

                if(sym.foreground != sym.background && visibility)
                {
                    auto fg = makeRGBA(display.getColor(sym.foreground));
                    ColorTransform tr = { multiply: fg | 0xff000000 };

                    auto symbolImage = getSymbolDrawBuf(sym.character);
                    auto fgGlyph = symbolImage.transformColors(tr);
                    bgGlyph.drawImage(0, 0, fgGlyph);
                    destroy(fgGlyph);
                    destroy(symbolImage);
                }

                cdbuf.drawImage(x * CHAR_SIZE_X + borderWidth, y * CHAR_SIZE_Y + borderWidth, bgGlyph);

                destroy(bgGlyph);
            }
    }

    private void placeSplashToBuf()
    {
        display.forEachSplashPixel(
            (x, y, c)
            {
                cdbuf.drawPixel(x + borderWidth, y + borderWidth, makeRGBA(c));
            }
        );
    }

    override void onDraw(DrawBuf buf)
    {
        assert(onScreenDraw !is null);
        onScreenDraw();

        if(visibility != Visibility.Visible)
            return;

        placeFrameToBuf();

        auto srcRect = Rect(0, 0, cdbuf.width, cdbuf.height);
        buf.drawRescaled(pos, cdbuf, srcRect);
        destroy(cdbuf);

        _needDraw = false;
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

    private ColorDrawBuf getSymbolDrawBuf(ubyte character)
    {
        auto ret = new ColorDrawBuf(CHAR_SIZE_X, CHAR_SIZE_Y);
        ret.fill(0xff00ff00);

        LEM1802.SymbolBitmap b = display.getSymbolBitmap(character);

        foreach(y; 0 .. CHAR_SIZE_Y)
        {
            foreach(x; 0 .. CHAR_SIZE_X)
            {
                bool isSet = display.getPixelOfSymbol(b, x, y);

                if(isSet)
                    ret.drawPixel(x, y, 0x00ffffff);
            }
        }

        return ret;
    }

    override bool wantsKeyTracking() { return true; }

    override bool onKeyEvent(KeyEvent e)
    {
        if(e.action == KeyAction.Text)
        {
            import dlangui.core.logger;
            import std.conv;
            Log.d("================ key event"~e.to!string);

            char code = e.text[0].to!string[0]; //FIXME: wtf?!

            // Numbers and capital letters
            if(code >= 0x30 && code <= 0x5a)
            {
                Log.d(">>>>> key pressed"~e.to!string);
                keyboard.keyPressed(code);
            }
        }

        return true;
    }
}
