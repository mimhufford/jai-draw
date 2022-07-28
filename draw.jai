main :: ()
{
    window.width = 800;
    window.height = 800;
    window.handle = create_window(window.width, window.height, "Draw", background_color_rgb = .[.08,.08,.08]);
    array_resize(*window.bitmap, window.width * window.height * 4);

    init_pen();

    while !window.quit
    {
        process_window_events();

        if input.keys[       27].went_down then window.quit = true;  // Esc
        if input.keys[      219].went_down then change_size(0.5);    // [
        if input.keys[      221].went_down then change_size(2.0);    // ]
        if input.keys[#char "1"].went_down then colour = colours[ 0];
        if input.keys[#char "2"].went_down then colour = colours[ 1];
        if input.keys[#char "3"].went_down then colour = colours[ 2];
        if input.keys[#char "4"].went_down then colour = colours[ 3];
        if input.keys[#char "5"].went_down then colour = colours[ 4];
        if input.keys[#char "6"].went_down then colour = colours[ 5];
        if input.keys[#char "7"].went_down then colour = colours[ 6];
        if input.keys[#char "8"].went_down then colour = colours[ 7];
        if input.keys[#char "9"].went_down then colour = colours[ 8];
        if input.keys[#char "0"].went_down then colour = colours[ 9];
        if input.keys[#char "E"].went_down then colour = colours[10];
        if input.keys[17].is_down && input.keys[#char "Z"].went_down then undo();
        if input.keys[17].is_down && input.keys[#char "N"].went_down then clear();

        if input.pressure > 0
        {
            s := get_active_stroke();
            s.colour = colour;
            p := array_add(*s.points);
            p.x = input.x;
            p.y = input.y;
            p.r = xx (input.pressure * size);
            window.dirty = true;
        }
        else
        {
            if strokes then strokes[strokes.count-1].alive = false;
        }

        if window.dirty
        {
            window.dirty = false;

            for s: strokes
            {
                for p: s.points
                {
                    fill :: (x: s32, y: s32)
                    {
                        if x < 0 return;
                        if y < 0 return;
                        if x >= window.width return;
                        if y >= window.height return;
                        index := (y * window.height + x) * 4;
                        window.bitmap[index + 0] = 255;
                        window.bitmap[index + 1] = 255;
                        window.bitmap[index + 2] = 255;
                        window.bitmap[index + 3] = 255;
                    }

                    for y: p.y-p.r .. p.y+p.r
                    {
                        for x: p.x-p.r .. p.x+p.r
                        {
                            fill(x, y);
                        }
                    }
                }
            }

            draw();
        }

        sleep_milliseconds(1);
    }
}

//
// Rendering
//

draw :: ()
{
    bmi : BITMAPINFO;
    bmi.bmiHeader.biSize = size_of(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = window.width;
    bmi.bmiHeader.biHeight = window.height;
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    StretchDIBits(GetDC(window.handle), 0, 0, window.width, window.height, 0, 0, window.width, window.height, window.bitmap.data, *bmi, 0, 0x00CC0020 /* SRCCOPY */);
}

//
// Helper procedures
//

get_active_stroke :: () -> *Stroke
{
    if !strokes return array_add(*strokes);
    last := *strokes[strokes.count - 1];
    if last.alive return last;
    return array_add(*strokes);
}

change_size :: (multiplier : float)
{
    size *= multiplier;
    if size < 0.5 size = 0.5;
}

undo :: () -> bool
{
    if strokes.count < 1 return false;
    window.dirty = true;
    array_reset(*strokes[strokes.count - 1].points);
    array_ordered_remove_by_index(*strokes, strokes.count - 1);
    return true;
}

clear :: ()
{
    while undo() {}
}

//
// Structs and data
//

size   := 15.0;
colour := colours[9];
strokes : [..]Stroke;

Stroke :: struct {
    colour : Vector4;
    points : [..]Point;
    alive := true;
}

Point :: struct {
    x : s32;
    y : s32;
    r : s32;
}

window : struct {
    handle    : HWND;
    width     : s32;
    height    : s32;
    quit      : bool;
    dirty    := true;
    last_draw : Apollo_Time;
    bitmap    : [..]u8;
}

input : struct {
    x         : s32;
    y         : s32;
    pressure  : float;
    keys      : [256]Key;
    prev_keys : [256]Key;
}

Key :: struct {
    is_down   : bool;
    went_down : bool;
}

colours :: Vector4.[
    .{0.9, 0.1, 0.1, 1}, //  0, shortcut key 1
    .{0.1, 0.9, 0.1, 1}, //  1, shortcut key 2
    .{0.1, 0.1, 0.9, 1}, //  2, shortcut key 3
    .{0.9, 1.0, 0.1, 1}, //  3, shortcut key 4
    .{1.0, 0.4, 0.0, 1}, //  4, shortcut key 5
    .{0.2, 0.9, 0.6, 1}, //  5, shortcut key 6
    .{0.9, 0.1, 0.9, 1}, //  6, shortcut key 7
    .{0.1, 0.9, 0.9, 1}, //  7, shortcut key 8
    .{1.0, 0.0, 0.5, 1}, //  8, shortcut key 9
    .{1.0, 1.0, 0.8, 1}, //  9, shortcut key 0
    .{.08, .08, .08, 1}, // 10, shortcut key E
];

//
// Win32 window message & input related
//

process_window_events :: ()
{
    input.prev_keys = input.keys;
    for * input.keys it.went_down = false;

    while true
    {
        msg: MSG;
        if !PeekMessageW(*msg, null, 0, 0, PM_REMOVE) break;
        TranslateMessage(*msg);
        DispatchMessageW(*msg);
    }
}

#add_context _windows_windowproc :: (handle: HWND, message: u32, wParam: WPARAM, lParam: LPARAM) -> s64 #c_call
{
    ctx: Context;
    ctx.allocator = Context.default_allocator;
    ctx.logger    = Context.default_logger;

    push_context ctx {

    if message ==
    {
        case WM_PAINT;
            draw();

        case WM_KEYDOWN; #through;
        case WM_SYSKEYDOWN;
            input.keys[wParam].is_down = true;
            if !input.prev_keys[wParam].is_down then input.keys[wParam].went_down = true;
            return 0; // Mark message as handled so alt doesn't cause window focus to change

        case WM_KEYUP; #through;
        case WM_SYSKEYUP;
            input.keys[wParam].is_down = false;

        case WM_QUIT; #through;
        case WM_CLOSE;
            window.quit = true;

        case WM_LBUTTONDOWN;
            // check specifically for a mouse click, not a pen down event
            if GetMessageExtraInfo() == 0 input.pressure = 1;

        case WM_LBUTTONUP;
            input.pressure = 0;

        case WM_MOUSEMOVE; #through;
        case WT_MESSAGE;
            point: POINT;
            GetCursorPos(*point);
            ScreenToClient(handle, *point);
            input.x = point.x;
            input.y = window.height - point.y;

            pressure : u32;
            if WTPacket && WTPacket(xx lParam, xx wParam, *pressure) {
                input.pressure = pressure / 8191.0;
            }
    }
    }

    return DefWindowProcW(handle, message, wParam, lParam);
}

//
// WinTab related
//

init_pen :: () -> bool
{
    // Load the dll
    dll := LoadLibraryA("Wintab32.dll");
    if !dll
    {
        print("Wintab32.dll not found\n");
        return false;
    }

    // Fetch procedures
    WTInfo   = cast(type_of(WTInfo))   GetProcAddress(dll, "WTInfoA");
    WTOpen   = cast(type_of(WTOpen))   GetProcAddress(dll, "WTOpenA");
    WTPacket = cast(type_of(WTPacket)) GetProcAddress(dll, "WTPacket");

    // Test for availability
    if !WTInfo(0, 0, null)
    {
        print("Wintab not available\n");
        return false;
    }

    // Set up which data we want to receive
    log_ctx : Log_Context;
    WTInfo(WTI_DDCTXS, 0, *log_ctx);
    log_ctx.pktData   = PK_NORMAL_PRESSURE;
    log_ctx.moveMask  = PK_NORMAL_PRESSURE;

    // Attach to our window
    ctx := WTOpen(window.handle, log_ctx, true);
    if !ctx
    {
        print("Wintab context couldn't be opened\n");
        return false;
    }

    return true;
}

// procedures
WTPacket : (ctx: u32, serial: u32, pressure: *u32) -> bool #foreign;
WTInfo   : (category: u32, index: u32, output: *void)         -> u32  #foreign;
WTOpen   : (window: HWND, log_ctx: Log_Context, enable: bool) -> u32  #foreign;

// constants
WT_MESSAGE         :: 32752;
WTI_DDCTXS         :: 400;
PK_NORMAL_PRESSURE :: 0x0400;

// structs
Log_Context :: struct {
    name:      [40]u8;
    options:   u32;
    status:    u32;
    locks:     u32;
    msgBase:   u32;
    device:    u32;
    pktRate:   u32;
    pktData:   u32;
    pktMode:   u32;
    moveMask:  u32;
    btnDnMask: u32;
    btnUpMask: u32;
    inOrgX:    s32;
    inOrgY:    s32;
    inOrgZ:    s32;
    inExtX:    s32;
    inExtY:    s32;
    inExtZ:    s32;
    outOrgX:   s32;
    outOrgY:   s32;
    outOrgZ:   s32;
    outExtX:   s32;
    outExtY:   s32;
    outExtZ:   s32;
    sensX:     u32;
    sensY:     u32;
    sensZ:     u32;
    sysMode:   bool;
    sysOrgX:   s32;
    sysOrgY:   s32;
    sysExtX:   s32;
    sysExtY:   s32;
    sysSensX:  u32;
    sysSensY:  u32;
}

//
// Imports
//

#import "Math";
#import "Basic";
#import "Windows";
#import "Window_Creation";