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
        is_down :: (k: Input.Key_Code) -> bool { return Input.input_button_states[k] & .DOWN != 0; }

        Input.update_window_events();

        // mouse moves
        if drawing add_point();
        if panning && is_down(.MOUSE_BUTTON_LEFT) pan();

        for Input.events_this_frame
        {
            went_down :: (k: Input.Key_Code) -> bool #expand { return it.type == .KEYBOARD && it.key_code == k && it.key_pressed && !it.repeat; }
            went_up   :: (k: Input.Key_Code) -> bool #expand { return it.type == .KEYBOARD && it.key_code == k && !it.key_pressed; }

            // quitting
            if it.type == .QUIT   quit = true;
            if went_down(.ESCAPE) quit = true;

            // colour selection
            if went_down(#char "1") set_colour(0);
            if went_down(#char "2") set_colour(1);
            if went_down(#char "3") set_colour(2);
            if went_down(#char "4") set_colour(3);
            if went_down(#char "5") set_colour(4);
            if went_down(#char "6") set_colour(5);
            if went_down(#char "7") set_colour(6);
            if went_down(#char "8") set_colour(7);
            if went_down(#char "9") set_colour(8);
            if went_down(#char "0") set_colour(9);

            // panning
            if is_down(.CTRL) && went_down(.MOUSE_BUTTON_LEFT) start_pan();
            if went_up(.MOUSE_BUTTON_LEFT)                     end_pan();

            // size
            if went_down(#char "[") change_size(0.5);
            if went_down(#char "]") change_size(2);

            // undo
            if is_down(.CTRL) && went_down(#char "Z") undo();

            // clear canvas
            if is_down(.CTRL) && went_down(#char "N") clear();

            // drawing
            if went_down(.MOUSE_BUTTON_LEFT) add_stroke();
            if went_up  (.MOUSE_BUTTON_LEFT) end_stroke();
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
        // Draw the circle for the 1st point immediately
        draw_circle(s.points[0] + offset, s.size, s.colour);

        for i: 1..s.points.count-1
        {
            // Consider 2 points at a time so we can draw the line between them
            p0 := s.points[i-1] + offset;
            p1 := s.points[i-0] + offset;

            // Draw the circle for the 2nd point
            draw_circle(p1, s.size, s.colour);

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