import dlangui;

mixin APP_ENTRY_POINT;

extern (C) int UIAppMain(string[] args)
{
    Window window = Platform.instance.createWindow("DCPU-16 emulator", null);

    window.mainWidget = parseML(q{
        VerticalLayout
        {
            TextWidget { text: "Hello World example for DlangUI"; fontSize: 150%; fontWeight: 800 }

            //~ ImageWidget { minWidth: 256; minHeight: 128; id: EMUL_0 }

            HorizontalLayout {
                Button { id: btnOk; text: "Ok" }
                Button { id: btnCancel; text: "Cancel" }
            }
        }
    });

    auto emulScr = new EmulatorScreenWidget("EMUL_SCREEN0");
    window.mainWidget.insertChild(emulScr, 1);

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

    size_t idx;
    disp.forEachPixel(
        (PaletteColor c)
        {
            //~ frame[idx] = makeRGBA(44,44,44,30);
            //~ frame[idx] = makeRGBA(
                    //~ c.r * 17,
                    //~ c.g * 17,
                    //~ c.b * 17,
                    //~ 0
                //~ );
            idx++;
        }
    );

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
    private ColorDrawBuf cdbuf;

    this(string id)
    {
        super(id);
        minWidth = 256;
        minHeight = 128;

        cdbuf = new ColorDrawBuf(X_RESOLUTION, Y_RESOLUTION);
        cdbuf.fill(123);

        Ref!DrawBuf r = cdbuf ;
        drawable = new ImageDrawable(r);
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
