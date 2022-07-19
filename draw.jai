window: Window_Type;
width  : s32 = 1920;
height : s32 = 1080;
last_draw : Apollo_Time;

colours :: Vector4.[
    .{0.9, 0.1, 0.1, 1}, // 0, shortcut key 1
    .{0.1, 0.9, 0.1, 1}, // 1, shortcut key 2
    .{0.1, 0.1, 0.9, 1}, // 2, shortcut key 3
    .{0.9, 1.0, 0.1, 1}, // 3, shortcut key 4
    .{1.0, 0.4, 0.0, 1}, // 4, shortcut key 5
    .{0.2, 0.9, 0.6, 1}, // 5, shortcut key 6
    .{0.9, 0.1, 0.9, 1}, // 6, shortcut key 7
    .{0.1, 0.9, 0.9, 1}, // 7, shortcut key 8
    .{1.0, 0.0, 0.5, 1}, // 8, shortcut key 9
    .{1.0, 1.0, 0.8, 1}, // 9, shortcut key 0
];

dirty := true;
drawing := false;
selected_colour := 9;
size := 4.0;
offset : Vector2;

strokes : [..]Stroke;

Stroke :: struct {
    colour : Vector4;
    size   : float;
    points : [..]Vector2;
}

main :: ()
{
    do_os_specific_initialisation();

    window = create_window(width, height, "Sketches");

    // Actual render size in pixels can be different from the window dimensions we specified above (for example on high-resolution displays on macOS/iOS).
    width, height = Simp.get_render_dimensions(window);

    Simp.set_render_target(window);

    quit := false;

    while !quit
    {
        // mouse moves
        if drawing && (Input.mouse_delta_x != 0 || Input.mouse_delta_y != 0) add_point();

        Input.update_window_events();

        for Input.events_this_frame
        {
            // quitting
            if it.type == .QUIT                                then  quit = true;
            if it.type == .KEYBOARD && it.key_code == .ESCAPE  then  quit = true;

            // colour selection
            if it.type == .KEYBOARD && it.key_code == #char "1" then set_colour(0);
            if it.type == .KEYBOARD && it.key_code == #char "2" then set_colour(1);
            if it.type == .KEYBOARD && it.key_code == #char "3" then set_colour(2);
            if it.type == .KEYBOARD && it.key_code == #char "4" then set_colour(3);
            if it.type == .KEYBOARD && it.key_code == #char "5" then set_colour(4);
            if it.type == .KEYBOARD && it.key_code == #char "6" then set_colour(5);
            if it.type == .KEYBOARD && it.key_code == #char "7" then set_colour(6);
            if it.type == .KEYBOARD && it.key_code == #char "8" then set_colour(7);
            if it.type == .KEYBOARD && it.key_code == #char "9" then set_colour(8);
            if it.type == .KEYBOARD && it.key_code == #char "0" then set_colour(9);

            // panning
            // @TODO: hook this up to key + mouse control
            if it.type == .KEYBOARD && it.key_code == #char "W" && it.key_pressed then pan(.{0, +10});
            if it.type == .KEYBOARD && it.key_code == #char "S" && it.key_pressed then pan(.{0, -10});
            if it.type == .KEYBOARD && it.key_code == #char "A" && it.key_pressed then pan(.{-10, 0});
            if it.type == .KEYBOARD && it.key_code == #char "D" && it.key_pressed then pan(.{+10, 0});

            // size
            if it.type == .KEYBOARD && it.key_code == #char "[" && it.key_pressed then change_size(0.5);
            if it.type == .KEYBOARD && it.key_code == #char "]" && it.key_pressed then change_size(2);

            // undo
            if it.type == .KEYBOARD && it.key_code == #char "Z" && it.key_pressed then undo();

            // clear canvas
            if it.type == .KEYBOARD && it.key_code == #char "N" && it.key_pressed then clear();

            // drawing
            if it.type == .KEYBOARD && it.key_code == .MOUSE_BUTTON_LEFT &&  it.key_pressed then add_stroke();
            if it.type == .KEYBOARD && it.key_code == .MOUSE_BUTTON_LEFT && !it.key_pressed then end_stroke();
        }

        draw_one_frame();
        sleep_milliseconds(10);
        reset_temporary_storage();
    }
}

undo :: () -> bool
{
    if drawing return false;
    if strokes.count < 1 return false;
    dirty = true;
    array_reset(*strokes[strokes.count - 1].points);
    array_ordered_remove_by_index(*strokes, strokes.count - 1);
    return true;
}

clear :: ()
{
    while undo() {}
}

change_size :: (multiplier : float)
{
    dirty = true;
    size *= multiplier;
    if size < 0.5 size = 0.5;
    if drawing
    {
        s := *strokes[strokes.count - 1];
        s.size = size;
    }
}

set_colour :: (colour : int)
{
    if selected_colour == colour return;
    dirty = true;
    selected_colour = colour;
    if drawing
    {
        s := *strokes[strokes.count - 1];
        s.colour = colours[selected_colour];
    }
}

pan :: (delta : Vector2)
{
    if delta.x == 0 && delta.y == 0 return;
    dirty = true;
    offset += delta;
}

add_stroke :: ()
{
    drawing = true;

    s := array_add(*strokes);
    s.colour = colours[selected_colour];
    s.size = size;

    add_point();
}

end_stroke :: ()
{
    drawing = false;
}

add_point :: ()
{
    dirty = true;

    array_add(*strokes[strokes.count - 1].points, get_cursor_position() - offset);
}

draw_one_frame :: ()
{
    // We only draw when the canvas is dirty so the GPU can idle most of the time.
    // But, because this is a DPI aware application, not rendering every frame means
    // the alt-tab preview won't show anything, and switching applications comes
    // back to a blank canvas until the next redraw. Rather than trying to handle
    // all the specific cases we just force a redraw every 250ms. Enough to feel
    // responsive but still allows the GPU to idle most of the time.
    if to_milliseconds(current_time_monotonic() - last_draw) > 250 then dirty = true;

    if !dirty return;

    dirty = false;

    Simp.clear_render_target(.08, .08, .08, 1);

    Simp.set_shader_for_color();

    for s: strokes
    {
        for i1: 1..s.points.count-1
        {
            i0 := i1 - 1;

            p0 := s.points[i0];
            p1 := s.points[i1];

            // @TODO: This should get switched to a specific shader at some point.

            // Calculate a vector between the 2 points currently being looked at so
            // the quad can be drawn with the correct angle between them. This will
            // cause breaks in the line when drawing a curve but it'll do for now.
            p01 := make_vector2(p0.x - p1.x, p0.y - p1.y);
            p01_normalised := p01 / length(p01);
            p01_scaled_to_size := p01_normalised * s.size;
            size_offset := make_vector2(-p01_scaled_to_size.y, p01_scaled_to_size.x);

            // Draw the line connecting the 2 points using the rotated
            // vector to give the line weight based on the size
            Simp.immediate_quad(
                p0 - size_offset + offset, p0 + size_offset + offset,
                p1 + size_offset + offset, p1 - size_offset + offset,
                s.colour, s.colour, s.colour, s.colour);
        }
    }

    Simp.swap_buffers(window);
    last_draw = current_time_monotonic();
}

Simp  :: #import "Simp";
Input :: #import "Input";
#import "Window_Creation";
#import "Basic";
#import "Math";
#import "Random";

#run {
    #if OS == .WINDOWS {
        #import "Windows_Resources";
        disable_runtime_console();
    }
}

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