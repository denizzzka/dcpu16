import dlangui;

mixin APP_ENTRY_POINT;

import dcpu16.emulator;

extern (C) int UIAppMain(string[] args)
{
    Window window = Platform.instance.createWindow("DCPU-16 emulator", null);

    window.mainWidget = parseML(q{
        VerticalLayout
        {
            TextWidget { text: "Hello World example for DlangUI"; fontSize: 150%; fontWeight: 800 }

            //~ ImageWidget { minWidth: 256; minHeight: 128; id: EMUL_0 }

            HorizontalLayout {
                Button { id: PAUSE; text: "Pause" }
                Button { id: STEP; text: "Step" }
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
    emulScr.setTimer(100);

    window.mainWidget.childById("PAUSE").addOnClickListener((Widget) {
            emulScr.isPaused = !emulScr.isPaused;
            return true;
        });

    window.mainWidget.childById("STEP").addOnClickListener((Widget) {
            emulScr.comp.cpu.step;
            comp.machineState.writeln;
            return true;
        });

    ushort[] scrFill =
    [
        0x7c01, 0xf000, 0x7c21, 0x8000, 0x0121, 0x8802, 0x8822, 0x7c32,
        0x8180, 0x7f81, 0x000d, 0x7f81, 0x0004, 0x7f81, 0x000d
    ];
    comp.load(scrFill);

    // show window
    window.show();

    // run message loop
    return Platform.instance.enterMessageLoop();
}

alias RGBA = uint;
alias RGBAframe = uint[PIXELS_NUM];

import dcpu16.emulator.devices.lem1802;

class EmulatorScreenWidget : ImageWidget
{
    public ColorDrawBuf cdbuf;
    private Computer comp;
    private LEM1802 display;
    bool isPaused = true;

    this(string id, Computer c, LEM1802 d)
    {
        super(id);
        minWidth = 256;
        minHeight = 128;

        cdbuf = new ColorDrawBuf(X_RESOLUTION, Y_RESOLUTION);
        cdbuf.fill(123);

        Ref!DrawBuf r = cdbuf ;
        drawable = new ImageDrawable(r);

        comp = c;
        display = d;
    }

    override bool onTimer(ulong id)
    {
        import std.stdio;

        if(!isPaused)
        {
            comp.cpu.step;
            comp.machineState.writeln;
        }

        return true;
    }

    private void refreshFrameToBuf()
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
        if(visibility != Visibility.Visible)
            return;

        super.onDraw(buf);

        Rect rc = _pos;
        applyMargins(rc);

        //~ auto saver = ClipRectSaver(buf, rc, alpha);
        applyPadding(rc);

        DrawableRef img = drawable;

        if (!img.isNull)
        {
            //~ auto sz = Point(showW, showH);
            //~ if (fitImage)
                //~ sz = imgSizeScaled(rc.width, rc.height);

            //~ applyAlign(rc, sz, Align.HCenter, valign);
            uint st = state;
            img.drawTo(buf, rc, st);
        }
    }
}
