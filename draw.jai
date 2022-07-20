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
panning := false;
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
        if drawing add_point();
        if panning && (Input.mouse_delta_x != 0 || Input.mouse_delta_y != 0) pan();

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
            if it.type == .KEYBOARD && it.key_code == .SPACEBAR then panning = xx it.key_pressed;

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

pan :: ()
{
    dirty = true;
    offset.x += Input.mouse_delta_x;
    offset.y -= Input.mouse_delta_y;
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
    points := *strokes[strokes.count - 1].points;
    position := get_cursor_position() - offset;

    // if the brush hasn't moved since the last point was added then don't add a point
    if points.count && (<<points)[points.count-1] == position return;

    array_add(points, position);
    dirty = true;
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
        for i: 2..s.points.count-1
        {
            // We consider three points at a time so that the vertices
            // for quads representing the lines can be calculated without
            // leaving missing triangles when the line changes direction

            p0 := s.points[i-2];
            p1 := s.points[i-1];
            p2 := s.points[i-0];

            // Calculate the offset vector for points 0 and 1
            p01 := make_vector2(p0.x - p1.x, p0.y - p1.y);
            p01_normalised := p01 / length(p01);
            p01_scaled_to_size := p01_normalised * s.size;
            p01_offset := make_vector2(-p01_scaled_to_size.y, p01_scaled_to_size.x);

            // Calculate the offset vector for points 1 and 2
            p12 := make_vector2(p1.x - p2.x, p1.y - p2.y);
            p12_normalised := p12 / length(p12);
            p12_scaled_to_size := p12_normalised * s.size;
            p12_offset := make_vector2(-p12_scaled_to_size.y, p12_scaled_to_size.x);

            // Draw the quad representing the line from p0 to p1
            Simp.immediate_quad(
                p0 - p01_offset + offset, p0 + p01_offset + offset,
                p1 + p01_offset + offset, p1 - p01_offset + offset,
                s.colour, s.colour, s.colour, s.colour);

            // Draw the quad which patches the potentially missing triangles around p1
            Simp.immediate_quad(
                p1 - p12_offset + offset, p1 + p01_offset + offset,
                p1 + p12_offset + offset, p1 - p01_offset + offset,
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