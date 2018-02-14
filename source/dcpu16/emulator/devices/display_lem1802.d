module dcpu16.emulator.devices.lem1802;

import dcpu16.emulator.idevice;
import dcpu16.emulator;

enum CHAR_SIZE_X = 4;
enum CHAR_SIZE_Y = 8;
enum X_RESOLUTION = 32;
enum Y_RESOLUTION = 12;
enum PIXELS_NUM = X_RESOLUTION * Y_RESOLUTION * CHAR_SIZE_X * CHAR_SIZE_Y;
static assert(PIXELS_NUM == 128 * 96);

class LEM1802 : IDevice
{
    uint id() const pure { return 0x7349f615; };
    uint manufacturer() const pure { return 0x1c6c8b36; };
    ushort ver() const pure { return 0x1802 ; };

    private const(ushort)* screen;
    private const(ushort)* font = defaultFont.ptr;
    private const(ushort)* palette = defaultPalette.ptr;
    private ubyte borderColor;

    bool isDisconnected() const { return screen is null; }

    this(Computer comp)
    {
        screen = &comp.mem[0x8000]; // de facto standard
    }

    void handleHardwareInterrupt(Computer comp)
    {
        with(InterruptActions)
        with(comp)
        with(cpu.regs)
        switch(A)
        {
            case MEM_MAP_SCREEN:
                screen = (B == 0) ? null : &mem[B];
                return;

            case MEM_MAP_FONT:
                font = (B == 0) ? defaultFont.ptr : &mem[B];
                return;

            case MEM_MAP_PALETTE:
                palette = (B == 0) ? defaultPalette.ptr : &mem[B];
                return;

            case SET_BORDER_COLOR:
                borderColor = B & 0xF;
                return;

            case MEM_DUMP_FONT:
                dump(mem, font[0 .. defaultFont.length], B);
                return;

            case MEM_DUMP_PALETTE:
                dump(mem, palette[0 .. defaultPalette.length], B);
                return;

            default:
                break;
        }
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

        return Symbol(screen[idx]);
    }

    const(Symbol) getSymbol(uint x, uint y) const
    {
        return getSymbol(x + y * X_RESOLUTION);
    }

    bool getPixel(uint x, uint y) const
    {
        auto symbolX = x / CHAR_SIZE_X;
        auto symbolY = y / CHAR_SIZE_Y;

        auto s = getSymbol(symbolX, symbolY);
        auto bitmap = getSymbolBitmap(s.character);

        auto relativeX = x % CHAR_SIZE_X;
        auto relativeY = y % CHAR_SIZE_Y;

        return getPixelOfSymbol(bitmap, relativeX, relativeY);
    }

    static bool getPixelOfSymbol(ushort[2] symbolBitmap, uint relativeX, uint relativeY) pure
    {
        assert(relativeX < CHAR_SIZE_X);
        assert(relativeY < CHAR_SIZE_Y);

        union CharBitArray
        {
            ushort[2] for_ctor;
            ubyte[4] ub_arr;
            alias ub_arr this;

            this(ushort[2] from) pure
            {
                import std.bitmanip: swapEndian;

                for_ctor[0] = swapEndian(from[0]);
                for_ctor[1] = swapEndian(from[1]);
            }
        }

        auto bitArray = CharBitArray(symbolBitmap);
        relativeY %= CHAR_SIZE_Y;

        auto ul = cast(ulong) bitArray[relativeX];
        import core.bitop: bt;
        return bt(&ul, relativeY) != 0;
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

    private ushort[2] getSymbolBitmap(ubyte character) pure const
    {
        const ushort* ptr = &font[character * 2];

        return ptr[0 .. 2];
    }

    void forEachPixel(void delegate(PaletteColor c) dg) const
    {
        for(ubyte y = 0; y < Y_RESOLUTION * CHAR_SIZE_Y; y++)
        {
            for(ubyte x = 0; x < X_RESOLUTION * CHAR_SIZE_X; x++)
            {
                const s = getSymbol(x / CHAR_SIZE_X, y / CHAR_SIZE_Y);
                const bitmap = getSymbolBitmap(s.character);

                PaletteColor c;

                if(getPixel(x, y))
                    c = getColor(s.foreground);
                else
                    c = getColor(s.background);

                dg(c);
            }
        }
    }

    // TODO: make it more faster
    RGB[PIXELS_NUM] getRgbFrame() const
    {
        RGB[PIXELS_NUM] ret;
        size_t currPixel;

        forEachPixel(
            (c)
            {
                ret[currPixel] = c.toRGB;
                currPixel++;
            }
        );

        assert(currPixel == PIXELS_NUM);

        return ret;
    }

    private PaletteColor getColor(ubyte paletteIndex) const
    {
        ushort c = palette[paletteIndex];

        return PaletteColor(c);
    }
}

unittest
{
    auto c = new Computer;
    auto d = new LEM1802(c);
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

enum InterruptActions : ushort
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

immutable ushort[256] defaultFont =
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

immutable ushort[16] defaultPalette =
[
	0x000, 0x00a, 0x0a0, 0x0aa,
	0xa00, 0xa0a, 0xa50, 0xaaa,
	0x555, 0x55f, 0x5f5, 0x5ff,
	0xf55, 0xf5f, 0xff5, 0xfff
];
