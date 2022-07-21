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
pan_start : Vector2;
offset_start : Vector2;
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
        is_down :: (k : Input.Key_Code) -> bool { return Input.input_button_states[k] == .DOWN; }

        Input.update_window_events();

        // mouse moves
        if drawing add_point();
        if panning && is_down(.MOUSE_BUTTON_LEFT) then pan();

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
            if it.type == .KEYBOARD && it.key_code == .CTRL &&  it.key_pressed then start_pan();
            if it.type == .KEYBOARD && it.key_code == .CTRL && !it.key_pressed then end_pan();

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

start_pan :: ()
{
    panning = true;
    pan_start = get_cursor_position();
    offset_start = offset;
}

end_pan :: ()
{
    panning = false;
}

pan :: ()
{
    dirty = true;
    offset = offset_start + get_cursor_position() - pan_start;
}

add_stroke :: ()
{
    if panning return;

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
        for i: 1..s.points.count-1
        {
            // Consider 2 points at a time so we can draw the line between them
            p0 := s.points[i-1] + offset;
            p1 := s.points[i-0] + offset;

            // Always draw the circle for the 2nd point
            draw_circle(p1, s.size, s.colour);

            // If we're on the first line also draw the circle for the 1st point
            if i == 1 draw_circle(p0, s.size, s.colour);

            // Calculate the offset vector for the line thickness
            p01 := make_vector2(p0.x - p1.x, p0.y - p1.y);
            p01_scaled_to_size := p01 / length(p01) * s.size;
            p01_offset := make_vector2(-p01_scaled_to_size.y, p01_scaled_to_size.x);

            // Draw the quad representing the line
            Simp.immediate_quad(
                p0 - p01_offset, p0 + p01_offset,
                p1 + p01_offset, p1 - p01_offset,
                s.colour, s.colour, s.colour, s.colour);
        }
    }

    Simp.swap_buffers(window);
    last_draw = current_time_monotonic();
}

draw_circle :: (p: Vector2, r: float, c: Vector4)
{
    segments :: 24;
    step :: 2 * 3.14159 / segments;

    #insert #run -> string
    {
        s: String_Builder;
        
        print_to_builder(*s, "sin_lut :: float.[");
        for 0..segments print_to_builder(*s, "%,", sin(cast(float)it * step));
        print_to_builder(*s, "];");

        print_to_builder(*s, "cos_lut :: float.[");
        for 0..segments print_to_builder(*s, "%,", cos(cast(float)it * step));
        print_to_builder(*s, "];");

        return builder_to_string(*s);
    };

    p3 := make_vector3(p.x, p.y, 0);

    for i: 0..segments-1
    {
        r1 := make_vector3(p.x + sin_lut[i+0] * r, p.y + cos_lut[i+0] * r, 0);
        r2 := make_vector3(p.x + sin_lut[i+1] * r, p.y + cos_lut[i+1] * r, 0);
        Simp.immediate_triangle(p3, r1, r2, c, c, c);
    }
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