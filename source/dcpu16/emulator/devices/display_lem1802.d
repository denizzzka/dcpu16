module dcpu16.emulator.devices.lem1802;

import dcpu16.emulator.idevice;
import dcpu16.emulator;

enum CHAR_SIZE_X = 4;
enum CHAR_SIZE_Y = 8;
enum X_RESOLUTION = 32;
enum Y_RESOLUTION = 12;
enum X_PIXELS = X_RESOLUTION * CHAR_SIZE_X;
enum Y_PIXELS = Y_RESOLUTION * CHAR_SIZE_Y;
enum PIXELS_NUM = X_PIXELS * Y_PIXELS;
static assert(PIXELS_NUM == 128 * 96);

class LEM1802 : IDevice
{
    override uint id() const pure { return 0x7349f615; };
    override uint manufacturer() const pure { return 0x1c6c8b36; };
    override ushort ver() const pure { return 0x1802; };

    private const(ushort)* screen;
    private const(ushort)* font;
    private const(ushort)* palette;
    private ubyte borderColor;
    bool isBlinkingVisible = true;
    void delegate(InterruptAction) onInterruptAction;
    private long splashTimeRemaining; /// in hnsecs (hectoseconds)

    bool isDisconnected() const { return screen is null; }

    this(Computer comp)
    {
        screen = &comp.mem[0x8000]; // de facto standard

        reset();
    }

    override void reset()
    {
        font = defaultFont.ptr;
        palette = defaultPalette.ptr;
        borderColor = 0;
        splashTimeRemaining = 25_000_000; // 2.5 seconds
    }

    override void handleHardwareInterrupt(Computer comp)
    {
        auto action = cast(InterruptAction) comp.cpu.regs.A;

        with(InterruptAction)
        with(comp)
        with(cpu.regs)
        switch(action)
        {
            case MEM_MAP_SCREEN:
                if(B != 0)
                    screen = &mem[B];
                break;

            case MEM_MAP_FONT:
                font = (B == 0) ? defaultFont.ptr : &mem[B];
                break;

            case MEM_MAP_PALETTE:
                palette = (B == 0) ? defaultPalette.ptr : &mem[B];
                break;

            case SET_BORDER_COLOR:
                borderColor = B & 0xF;
                break;

            case MEM_DUMP_FONT:
                dump(mem, font[0 .. defaultFont.length], B);
                return;

            case MEM_DUMP_PALETTE:
                dump(mem, palette[0 .. defaultPalette.length], B);
                return;

            default:
                break;
        }

        if(onInterruptAction !is null)
            onInterruptAction(action);
    }

    private void dump(Memory mem, const(ushort)[] from, ushort to) pure
    {
        // cutt to fit into memory, if necessary
        if(to + from.length > mem.length)
            from.length = mem.length - to;

        mem[to .. to + from.length] = from[];
    }

    const(Symbol) getSymbol(size_t idx) const
    {
        assert(idx < 386);
        assert(!isSplashDisplayed);

        return Symbol(screen[idx]);
    }

    const(Symbol) getSymbol(uint x, uint y) const
    {
        return getSymbol(x + y * X_RESOLUTION);
    }

    alias SymbolBitmap = ushort[2];

    bool getPixel(uint x, uint y) const
    {
        assert(!isSplashDisplayed);

        auto symbolX = x / CHAR_SIZE_X;
        auto symbolY = y / CHAR_SIZE_Y;

        auto s = getSymbol(symbolX, symbolY);
        SymbolBitmap bitmap = getSymbolBitmap(s.character);

        auto relativeX = x % CHAR_SIZE_X;
        auto relativeY = y % CHAR_SIZE_Y;

        return getPixelOfSymbol(bitmap, relativeX, relativeY);
    }

    static bool getPixelOfSymbol(SymbolBitmap symbolBitmap, uint relativeX, uint relativeY) pure
    {
        assert(relativeX < CHAR_SIZE_X);
        assert(relativeY < CHAR_SIZE_Y);

        union CharBitArray
        {
            ushort[2] for_ctor;
            ubyte[4] ub_arr;

            this(ushort[2] from) pure
            {
                import std.bitmanip: swapEndian;

                for_ctor[0] = swapEndian(from[0]);
                for_ctor[1] = swapEndian(from[1]);
            }
        }

        auto bitArray = CharBitArray(symbolBitmap);
        relativeY %= CHAR_SIZE_Y;

        assert(relativeY < 8);

        ubyte ul = bitArray.ub_arr[relativeX];
        return bt(ul, cast(ubyte) relativeY) != 0;
    }
    unittest
    {
        /// 'F'
        ushort[2] f_img =
            [
                0b11111111_00001001,
                0b00001001_00000000
            ];

        immutable bool[][] pending =
        [
            [1,1,1,0],
            [1,0,0,0],
            [1,0,0,0],
            [1,1,1,0],
            [1,0,0,0],
            [1,0,0,0],
            [1,0,0,0],
            [1,0,0,0],
        ];

        foreach(y; 0 .. 8)
            foreach(x; 0 .. 4)
                assert(pending[y][x] == getPixelOfSymbol(f_img, x, y));
    }

    SymbolBitmap getSymbolBitmap(ubyte character) pure const
    {
        const ushort* ptr = &font[character * 2];

        return ptr[0 .. 2];
    }

    void forEachPixel(void delegate(ubyte x, ubyte y, PaletteColor c) dg) const
    {
        assert(!isSplashDisplayed);

        for(ubyte y = 0; y < Y_RESOLUTION * CHAR_SIZE_Y; y++)
        {
            for(ubyte x = 0; x < X_RESOLUTION * CHAR_SIZE_X; x++)
            {
                const s = getSymbol(x / CHAR_SIZE_X, y / CHAR_SIZE_Y);

                PaletteColor c;

                bool visible = isBlinkingVisible | !s.blinking;

                c = (visible && getPixel(x, y))
                    ? getColor(s.foreground)
                    : getColor(s.background);

                dg(x, y, c);
            }
        }
    }

    // TODO: make it more faster
    RGB[PIXELS_NUM] getRgbFrame() const
    {
        RGB[PIXELS_NUM] ret;
        size_t currPixel;

        forEachPixel(
            (x, y, c)
            {
                ret[currPixel] = c.toRGB;
                currPixel++;
            }
        );

        assert(currPixel == PIXELS_NUM);

        return ret;
    }

    PaletteColor getColor(ubyte paletteIdx) const
    {
        ushort c = isSplashDisplayed ? defaultPalette[paletteIdx] : palette[paletteIdx];

        return PaletteColor(c);
    }

    PaletteColor getBorderColor() const
    {
        if(isSplashDisplayed)
            return getColor(0x7);
        else
            return getColor(borderColor);
    }

    /**
     * Turn switch state of blinking symbols
     *
     * Recommended calling interval:
     * The Spectrum's 'FLASH' effect: every 16 frames (50 fps), the ink and paper of all flashing bytes is swapped
    */
    void switchBlink()
    {
        isBlinkingVisible = !isBlinkingVisible;
    }

    void splashClock(long interval)
    {
        if(splashTimeRemaining > 0)
            splashTimeRemaining -= interval;
    }

    bool isSplashDisplayed() const pure
    {
        return splashTimeRemaining > 0;
    }

    void forEachSplashPixel(void delegate(ubyte x, ubyte y, PaletteColor c) dg) const
    {
        assert(isSplashDisplayed);

        foreach(ubyte y; 0 .. Y_PIXELS)
            foreach(ubyte x; 0 .. X_PIXELS)
            {
                enum fakeBorderWidth = 8;
                enum fakeBorderHeight = 7;
                PaletteColor c;

                if(
                    (x >= fakeBorderWidth && x <= X_PIXELS - fakeBorderWidth) &&
                    (y >= fakeBorderHeight && y <= Y_PIXELS - fakeBorderHeight)
                )
                {
                    if(splashTimeRemaining > 15_000_000)
                    {
                        enum yPixels1_3 = (Y_PIXELS - fakeBorderHeight*2)/3; // 1/3 of pixels on this "zx" screen
                        auto relY = y - fakeBorderHeight;

                        if
                        (
                            splashTimeRemaining < 20_800_000 &&
                            (x % 4 == 0) // red line at every column
                        )
                        {
                            if
                            (
                                // upper dotted lines
                                (relY % 4 == 0 && splashTimeRemaining > 20_000_000) ||
                                // dotted lines at middle of the screen
                                (relY % 4 == 0 && relY >= yPixels1_3 && splashTimeRemaining > 19_700_000) ||
                                // solid lines at bottom
                                (relY % 2 == 0 && relY >= yPixels1_3*2 && splashTimeRemaining > 19_300_000)
                            )
                            {
                                c = getColor(0x4); // red lines
                            }
                            else
                            {
                                c = getColor(0x0);
                            }
                        }
                    }
                    else
                        c = getCopyrightPixels(x, y);
                }
                else // draw fake border
                {
                    c = getColor(0x7);
                }

                dg(x, y, c);
            }
    }

    private PaletteColor getCopyrightPixels(byte x, byte y) const
    {
        enum w = 93;
        enum h = 3;
        enum letterWidth = 3;

        // start coords
        enum x0 = CHAR_SIZE_X * 2;
        enum y0 = letterWidth * 29;

        x -= x0;
        y -= y0;

        bool pixel;

        if(
            (x >= 0 && x < w) &&
            (y >= 0 && y < h)
        )
        {
            pixel = nyaResearchLtd[x + y * w] != 0;
        }

        return pixel
            ? getColor(0x0)
            : getColor(0x7); // default ZX background color
    }
}

unittest
{
    auto c = new Computer;
    auto d = new LEM1802(c);
    d.splashTimeRemaining = 0;
    c.attachDevice = d;


    c.mem[0x8000] = 0b0111_1110_0_0000000 + '1'; // colored nonblinking '1'
    c.mem[0x8001] = '2';
    c.mem[0x8002] = '3';
    c.mem[0x8000 + 32] = 'a';
    c.mem[0x8000 + 33] = 0b0101_0110_1_0000000 + 'b';
    c.mem[0x8000 + 34] = 'c';

    assert(d.getSymbol(0).character == '1');
    assert(d.getSymbol(1).character == '2');
    assert(d.getSymbol(2).character == '3');
    assert(d.getSymbol(32).character == 'a');
    assert(d.getSymbol(33).character == 'b');
    assert(d.getSymbol(34).character == 'c');

    assert(d.getPixel(5, 4) == true);
    assert(d.getPixel(6, 4) == false);

    auto f = d.getRgbFrame;

    assert(f[0] == RGB(255, 255, 85));
    assert(f[1] == RGB(170, 170, 170));
    assert(f[4] == RGB(0, 0, 0));
    assert(f[1028] == RGB(170, 0, 170));
    assert(f[1029] == RGB(170, 85, 0));
}

import std.bitmanip: bitfields;

struct Symbol
{
    union
    {
        ushort word;

        mixin(bitfields!(
            ubyte, "character",  7,
            bool,  "blinking",   1,
            ubyte, "background", 4,
            ubyte, "foreground", 4,
        ));
    }
}

struct PaletteColor
{
    union
    {
        ushort word;

        mixin(bitfields!(
            ubyte, "b", 4,
            ubyte, "g", 4,
            ubyte, "r", 4,
            ubyte, "",  4,
        ));
    }

    RGB toRGB() const
    {
        RGB s;

        s.r += r; s.r *= 17;
        s.g += g; s.g *= 17;
        s.b += b; s.b *= 17;

        return s;
    }
}

enum InterruptAction : ushort
{
    MEM_MAP_SCREEN,
    MEM_MAP_FONT,
    MEM_MAP_PALETTE,
    SET_BORDER_COLOR,
    MEM_DUMP_FONT,
    MEM_DUMP_PALETTE,
}

struct RGB
{
    ubyte r, g, b;
}

private immutable ushort[256] defaultFont =
[
    0xb79e, 0x388e, 0x722c, 0x75f4, 0x19bb, 0x7f8f, 0x85f9, 0xb158,
    0x242e, 0x2400, 0x082a, 0x0800, 0x0008, 0x0000, 0x0808, 0x0808,
    0x00ff, 0x0000, 0x00f8, 0x0808, 0x08f8, 0x0000, 0x080f, 0x0000,
    0x000f, 0x0808, 0x00ff, 0x0808, 0x08f8, 0x0808, 0x08ff, 0x0000,
    0x080f, 0x0808, 0x08ff, 0x0808, 0x6633, 0x99cc, 0x9933, 0x66cc,
    0xfef8, 0xe080, 0x7f1f, 0x0701, 0x0107, 0x1f7f, 0x80e0, 0xf8fe,
    0x5500, 0xaa00, 0x55aa, 0x55aa, 0xffaa, 0xff55, 0x0f0f, 0x0f0f,
    0xf0f0, 0xf0f0, 0x0000, 0xffff, 0xffff, 0x0000, 0xffff, 0xffff,
    0x0000, 0x0000, 0x005f, 0x0000, 0x0300, 0x0300, 0x3e14, 0x3e00,
    0x266b, 0x3200, 0x611c, 0x4300, 0x3629, 0x7650, 0x0002, 0x0100,
    0x1c22, 0x4100, 0x4122, 0x1c00, 0x1408, 0x1400, 0x081c, 0x0800,
    0x4020, 0x0000, 0x0808, 0x0800, 0x0040, 0x0000, 0x601c, 0x0300,
    0x3e49, 0x3e00, 0x427f, 0x4000, 0x6259, 0x4600, 0x2249, 0x3600,
    0x0f08, 0x7f00, 0x2745, 0x3900, 0x3e49, 0x3200, 0x6119, 0x0700,
    0x3649, 0x3600, 0x2649, 0x3e00, 0x0024, 0x0000, 0x4024, 0x0000,
    0x0814, 0x2200, 0x1414, 0x1400, 0x2214, 0x0800, 0x0259, 0x0600,
    0x3e59, 0x5e00, 0x7e09, 0x7e00, 0x7f49, 0x3600, 0x3e41, 0x2200,
    0x7f41, 0x3e00, 0x7f49, 0x4100, 0x7f09, 0x0100, 0x3e41, 0x7a00,
    0x7f08, 0x7f00, 0x417f, 0x4100, 0x2040, 0x3f00, 0x7f08, 0x7700,
    0x7f40, 0x4000, 0x7f06, 0x7f00, 0x7f01, 0x7e00, 0x3e41, 0x3e00,
    0x7f09, 0x0600, 0x3e61, 0x7e00, 0x7f09, 0x7600, 0x2649, 0x3200,
    0x017f, 0x0100, 0x3f40, 0x7f00, 0x1f60, 0x1f00, 0x7f30, 0x7f00,
    0x7708, 0x7700, 0x0778, 0x0700, 0x7149, 0x4700, 0x007f, 0x4100,
    0x031c, 0x6000, 0x417f, 0x0000, 0x0201, 0x0200, 0x8080, 0x8000,
    0x0001, 0x0200, 0x2454, 0x7800, 0x7f44, 0x3800, 0x3844, 0x2800,
    0x3844, 0x7f00, 0x3854, 0x5800, 0x087e, 0x0900, 0x4854, 0x3c00,
    0x7f04, 0x7800, 0x047d, 0x0000, 0x2040, 0x3d00, 0x7f10, 0x6c00,
    0x017f, 0x0000, 0x7c18, 0x7c00, 0x7c04, 0x7800, 0x3844, 0x3800,
    0x7c14, 0x0800, 0x0814, 0x7c00, 0x7c04, 0x0800, 0x4854, 0x2400,
    0x043e, 0x4400, 0x3c40, 0x7c00, 0x1c60, 0x1c00, 0x7c30, 0x7c00,
    0x6c10, 0x6c00, 0x4c50, 0x3c00, 0x6454, 0x4c00, 0x0836, 0x4100,
    0x0077, 0x0000, 0x4136, 0x0800, 0x0201, 0x0201, 0x0205, 0x0200,
];

private immutable ushort[16] defaultPalette =
[
	0x000, 0x00a, 0x0a0, 0x0aa,
	0xa00, 0xa0a, 0xa50, 0xaaa,
	0x555, 0x55f, 0x5f5, 0x5ff,
	0xf55, 0xf5f, 0xff5, 0xfff
];

private immutable nyaResearchLtd = cast(immutable ubyte[]) import("splash_string.data");

// TODO: Phobos core.bitop.bt is glitches in release versions, so I made my own
/// Checks bit
private bool bt(ubyte value, ubyte bit) pure
{
    assert(bit < 8);

    auto t = value >>> bit;
    return t % 2 != 0;
}
