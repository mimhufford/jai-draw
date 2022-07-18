window: Window_Type;
width  : s32 = 1920;
height : s32 = 1080;

dirty := true;
drawing := false;

strokes : [..]Stroke;

Stroke :: struct {
    colour   : Vector4;
    pressure : float;
    points : [..]Vector2;
}

main :: ()
{
    // Doing this adds the first Stroke to the strokes collection so that we're ready to go
    add_point();

    do_os_specific_initialisation();

    window = create_window(width, height, "Sketches");
    
    // Actual render size in pixels can be different from the window dimensions we specified above (for example on high-resolution displays on macOS/iOS).
    width, height = Simp.get_render_dimensions(window);

    Simp.set_render_target(window);
    
    quit := false;

    while !quit
    {
        if drawing && (Input.mouse_delta_x != 0 || Input.mouse_delta_y != 0) add_point();

        Input.update_window_events();

        for Input.events_this_frame
        {
            if it.type == .QUIT                                then  quit = true;
            if it.type == .KEYBOARD && it.key_code == .ESCAPE  then  quit = true;

            if it.type == .KEYBOARD && it.key_code == .MOUSE_BUTTON_LEFT
            {
                drawing = xx it.key_pressed;
                add_point();
            }
        }

        draw_one_frame();
        sleep_milliseconds(10);
        reset_temporary_storage();
    }
}

add_point :: ()
{
    dirty = true;

    if drawing {
        s := *strokes[strokes.count - 1];
        p := get_cursor_position();
        array_add(*s.points, p);
    } else {
        s : Stroke;
        s.colour = make_vector4(1, random_get_zero_to_one(), random_get_zero_to_one(), 1);
        s.pressure = random_get_within_range(1, 5);
        array_add(*strokes, s);
    }
}

draw_one_frame :: ()
{
    // @TODO: let this update every 100ms or something in case of redraw issues
    if !dirty return;

    dirty = false;

    Simp.clear_render_target(.15, .08, .08, 1);
    
    Simp.set_shader_for_color();

    for s: strokes {
        for i1: 1..s.points.count-1 {
            i0 := i1 - 1;

            // @TODO: need to calculate the angle for the line properly
            pp0 := s.points[i0];
            pp1 := s.points[i1];

            p0 := make_vector2(pp0.x - s.pressure, pp0.y + s.pressure);
            p1 := make_vector2(pp0.x + s.pressure, pp0.y - s.pressure);
            p2 := make_vector2(pp1.x + s.pressure, pp1.y - s.pressure);
            p3 := make_vector2(pp1.x - s.pressure, pp1.y + s.pressure);
            Simp.immediate_quad(p0, p1, p2, p3, s.colour, s.colour, s.colour, s.colour);
        }
    }

    Simp.swap_buffers(window);
}

Simp  :: #import "Simp";
Input :: #import "Input";
#import "Window_Creation";
#import "Basic"()(MEMORY_DEBUGGER=true);
#import "Math";
#import "Random";

// #run {
//     #if OS == .WINDOWS {
//         #import "Windows_Resources";
//         disable_runtime_console();
//     }
// }

get_cursor_position :: () -> Vector2
{
    position : Vector2;

    #if OS == .WINDOWS
    {
        #import "Windows";
        pos : POINT;
        GetCursorPos(*pos);
        ScreenToClient(window, *pos);
        position.x = xx pos.x;
        position.y = xx (height - pos.y);
    }
    else
    {
        assert(false);
    }

    return position;
}

do_os_specific_initialisation :: ()
{
    #if OS == .WINDOWS
    {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1); // Windows is very bad at thread-switching by default unless you do this
    }
}