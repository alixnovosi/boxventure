pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

-- button reference
-- 0 left
-- 1 right
-- 2 up
-- 3 down
-- 4 'o'
-- 5 'x'

function update_camera_pos()
    camera_move_speed = 2

    -- todo think more about camera windows
    camera_obj.x = player.x - camera_offset

    if (camera_obj.y + camera_offset) - player.y > cell_size then
        camera_obj.y -= camera_move_speed
    elseif player.y - (camera_obj.y + camera_offset) > cell_size then
        camera_obj.y += camera_move_speed
    end
end

function move_player()
    local dx = 0
    local dy = 0

    -- 0 left
    if btn(0) then
        dx -= player.move_speed
        player.flipped = true
    end

    -- 1 right
    if btn(1) then
        dx += player.move_speed
        player.flipped = false
    end

    dy += player.vv * 1

    if btn(4) then
        handle_use()
    end

    -- reset
    if btnp(4) and btnp(5) then
        reset()
    end

    apply_player_move(dx, dy)
end

function update_vv()
    rows, cols = get_player_cells()
    player_bottom = flr(player.y + (cell_size / 2) + (player.height / 2))
    bottom_row = to_cell(player_bottom, false)

    collidable_below = false
    for col in all(cols) do
        if is_collidable(col, bottom_row+1) then
            collidable_below = true
            break
        end
    end

    on_ground = false
    if collidable_below and (player_bottom % cell_size) == 0 then
        on_ground = true
    end

    -- apply jump if on ground. lock jump after some frames to allow variable height and cap jump.
    if btn(2) and not player.jump_locked then
        player.vv += player.jump_acc * 1

        if player.jump_started then
            player.jump_frames += 1

            if player.jump_frames >= player.max_jump_frames then
                player.jump_started = false
                player.jump_locked = true
                player.jump_frames = 0
            end
        else
            player.jump_started = true
            player.jump_frames += 1
        end
    end

    is_term_v = at_terminal_velocity()

    -- shouldn't apply gravity if we're on the ground, or if terminal velocity is reached.
    if not on_ground and not is_term_v then

        dv = level.grav_acc * 1

        if player.term_v < player.vv + dv then
            player.vv = player.term_v
        else
            player.vv += (level.grav_acc * 1)
        end
    end

    -- velocity should zero out on ground
    if on_ground and player.vv > 0 then
        player.vv = 0
        if player.jump_locked then
            player.jump_locked = false
        end
    end

    -- I'm not even sure how this happened
    if player.vv == -0 then player.vv = 0 end
end

function at_terminal_velocity()
    if (player.vv / abs(player.vv)) != (level.grav_acc / abs(level.grav_acc)) then
        return false
    end

    if (player.vv < player.term_v) return false

    return true
end

function handle_use()
    -- use from center of player
    col = to_cell(flr(player.x + player.width / 2))
    row = to_cell(flr(player.y + player.height / 2))

    if level.sign_open then
        level.sign_open = false
    end

    -- exit
    sprite = mget(col, row)
    if fget(sprite, 1) then
        run_credits()
    elseif list_compare(sprite, gen_list(37)) and not level.sign_open then

        -- TODO figure out why this isn't working - if you're to the right
        -- you get a blank sign without the if fix there
        local c,r = get_actual_cell(col, row, 37, sprite)
        read_sign(c, r)
        if level.last_sign_text != "" then
            level.sign_open = true
        end
    else
        -- this is weird because grab isn't really centered and ends up
        -- biased to upper left, I think.
        -- so for left/up we only need to go one cell up, for down/right 2
        if btn(0) then
            touch_object(col, row)
            touch_object(col-1, row)
            touch_object(col-2, row)
        elseif btn(1) then
            touch_object(col, row)
            touch_object(col+2, row)
            touch_object(col+2, row)
        elseif btn(2) then
            touch_object(col, row-0)
            touch_object(col, row-1)
            touch_object(col, row-2)
        elseif btn(3) then
            touch_object(col, row+0)
            touch_object(col, row+1)
            touch_object(col, row+2)
        else
            touch_object(col, row)
        end
    end
end

-- get actual cell when we did a fuzzy pick and have the cell to the right or something
-- assumes square sprite
function get_actual_cell(col, row, target_sprite, actual_sprite)
    dc = target_sprite - actual_sprite
    dr = (target_sprite - actual_sprite) % sprites_per_row

    return col+dc, row+dr
end

-- generate a list of sprites based on a given sprite
-- assumes you've given the upper-left corner of a spritescale x spritescale sprite
function gen_list(sprite)
    res = {}
    count = 1
    for c=0, spritescale-1 do
        for r=0, spritescale-1 do
            res[count] = sprite + c + (r * sprites_per_row)
            count += 1
        end
    end

    return res
end

-- check if square in a list of sprites
function list_compare(target, sprites)
    for sprite in all(sprites) do
        if target == sprite then return true end
    end

    return false
end

function touch_object(col, row)
    sprite = mget(col, row)

    -- so far just boxes
    box_sprite = 5
    if list_compare(sprite, gen_list(box_sprite)) then
        local c,r = get_actual_cell(col, row, box_sprite, sprite)

        -- touch box
        box_was_touched = false
        for box in all(level.boxes) do
            if box.x * spritescale == c and box.y * spritescale == r and not box.touched then
                box.touched = true
                box_was_touched = true
                break
            end
        end

        -- update the sign tracking box touches
        -- TODO find a less awful way to do this
        -- TODO there's a lot of awful things in this file honestly
        if box_was_touched then
            for sign in all(level.signs) do
                if sign.vars != nil then
                    for key, value in pairs(sign.vars) do
                        if key == "box_touch_count" then
                            sign.vars.box_touch_count += 1
                            break
                        end
                    end
                end
            end
        end
    end

    orb_sprite = 35
    if list_compare(sprite, gen_list(orb_sprite)) then
        local c,r = get_actual_cell(col, row, orb_sprite, sprite)

        -- touch orb
        orb_was_touched = false
        for orb in all(level.orbs) do
            if orb.x * spritescale == c and orb.y * spritescale == r and not orb.touched then
                orb.touched = true
                orb_was_touched = true
                break
            end
        end

        -- update the sign tracking orb touches
        if orb_was_touched then
            for sign in all(level.signs) do
                if sign.vars != nil then
                    for key, value in pairs(sign.vars) do
                        if key == "orb_touch_count" then
                            sign.vars.orb_touch_count += 1
                            break
                        end
                    end
                end
            end
        end
    end
end

function draw_sign()
    if not level.sign_open then
        level.last_sign_text = ""
        return
    end

    text_color = 6
    text_offset = 4
    border_color = 6
    textbox_bg_color = 5
    off_x, off_y = camera_relative_top_left()

    textbox_pos = {
        x0 = off_x + cell_size,
        y0 = off_y,
        x1 = off_x + 7 * cell_size - 1,
        y1 = off_y + 2 * cell_size,
    }

    -- two-line border to look cool.
    rect(textbox_pos.x0, textbox_pos.y0, textbox_pos.x1, textbox_pos.y1, border_color)
    rectfill(textbox_pos.x0 + 1, textbox_pos.y0 + 1, textbox_pos.x1 - 1, textbox_pos.y1 - 1,
        textbox_bg_color)
    rect(textbox_pos.x0 + 2, textbox_pos.y0 + 2, textbox_pos.x1 - 2, textbox_pos.y1 - 2,
        border_color)
    print(level.last_sign_text, textbox_pos.x0 + text_offset, textbox_pos.y0 + text_offset,
        text_color)
end

-- this function will be easier if it always gets the upper-left col/row
function read_sign(col, row)
    for sign in all(level.signs) do
        if sign.x * spritescale == col and sign.y * spritescale == row then
            if sign.is_dynamic then
                text = str_mult_replace(sign.text, sign.vars)
                level.last_sign_text = text
            else
                level.last_sign_text = sign.text
            end
        end
    end
end

function update_menu()
    if btnp(4) then
        is_menu = false
    end
end

function draw_menu()
    -- fill screen
    rectfill(0, 0, 1000, 1000, 6)

    -- draw upper text box
    rect(base_cell_size-2, base_cell_size-2, (15 * base_cell_size)+2, (6 * base_cell_size)+2, 5)
    rect(base_cell_size-1, base_cell_size-1, (15 * base_cell_size)+1, (6 * base_cell_size)+1, 6)
    rectfill(base_cell_size, base_cell_size, 15 * base_cell_size, 6 * base_cell_size, 5)

    -- title and dev
    print("box\nventure", base_cell_size + 2, base_cell_size + 2, 6)
    print("BY ALIXNOVOSI", base_cell_size + 2, (base_cell_size * 4) + 10, 6)

    -- boxes for styyyyyyle
    spr(5, (cell_size * 6), (cell_size * 2)-2, 2, 2)
    spr(5, (cell_size * 6), (cell_size * 1)-1, 2, 2)
    spr(5, (cell_size * 5)+1, (cell_size * 2)-2, 2, 2)

    -- draw bottom text box
    rect((base_cell_size)-2, (base_cell_size*9)-2, (base_cell_size*15)+2, (base_cell_size*11)+2, 5)
    rect((base_cell_size)-1, (base_cell_size*9)-1, (base_cell_size*15)+1, (base_cell_size*11)+1, 6)
    rectfill(base_cell_size, base_cell_size*9, base_cell_size*15, base_cell_size*11, 5)

    -- bottom text
    print("press (O) to start", (base_cell_size)+2, (base_cell_size*9) + 2, 6)
end

function run_credits()
    is_done = true
    credits.x = player.x - (4 * cell_size)
    credits.y = player.y - cell_size
end

function draw_credits()
    print(credits.text, credits.x, credits.y, 7)
end

function move_credits()
    if (btn(0)) then credits.x -= player.move_speed end
    if (btn(1)) then credits.x += player.move_speed end
    if (btn(2)) then credits.y -= player.move_speed end
    if (btn(3)) then credits.y += player.move_speed end

    -- exit credits on button 1
    if btnp(4) then
        camera(0, 0)
        _init()
    end
end

function get_player_cells()
    player_left = flr(player.x + (cell_size / 2) - (player.width / 2))
    player_top = flr(player.y + (cell_size / 2) - (player.height / 2))
    player_right = flr(player.x + (cell_size / 2) + (player.width / 2))
    player_bottom = flr(player.y + (cell_size / 2) + (player.height / 2))

    -- get rows we're in
    top_row = to_cell(player_top, true)
    bottom_row = to_cell(player_bottom)

    rows = {}
    rows[1] = top_row
    if bottom_row > top_row then
        for i=top_row+1, bottom_row do
            rows[#rows+1] = i
        end
    end

    -- get cols we're in
    left_col = to_cell(player_left, true)
    right_col = to_cell(player_right)

    cols = {}
    cols[1] = left_col
    if right_col > left_col then
        for i=left_col+1, right_col do
            cols[#cols+1] = i
        end
    end

    return rows, cols
end

function apply_player_move(dx, dy)
    rows, cols = get_player_cells()

    -- todo find ways to dedupe
    if dx > 0 then
        -- move to square edge
        dist_to_cell_edge = ((right_col+1) * base_cell_size) - player_right
        if dist_to_cell_edge >= dx then
            player.x += dx
        else
            player.x += dist_to_cell_edge
            dx -= dist_to_cell_edge

            -- see if we can continue moving
            can_move = true
            for row in all(rows) do
                coll = is_collidable(right_col+1, row)
                if coll then
                    can_move = false
                    break
                end
            end

            if can_move then
                player.x += dx
            end
        end
    elseif dx < 0 then
        -- move to square edge
        dist_to_cell_edge = player_left - (left_col * base_cell_size)
        if dist_to_cell_edge >= abs(dx) then
            player.x += dx
        else
            player.x -= dist_to_cell_edge
            dx += dist_to_cell_edge

            -- see if we can continue moving
            can_move = true
            for row in all(rows) do
                coll = is_collidable(left_col-1, row)
                if coll then
                    can_move = false
                    break
                end
            end

            if can_move then
                player.x += dx
            end
        end
    end

    if dy > 0 then
        -- move to square edge
        dist_to_cell_edge = ((bottom_row+1) * base_cell_size) - player_bottom
        if dist_to_cell_edge >= dy then
            player.y += dy
        else
            player.y += dist_to_cell_edge
            dy -= dist_to_cell_edge

            -- see if we can continue moving
            can_move = true
            for col in all(cols) do
                if is_collidable(col, bottom_row+1) then
                    can_move = false
                    break
                end
            end

            if can_move then
                player.y += dy
            end

        end
    elseif dy < 0 then
        -- move to square edge
        dist_to_cell_edge = player_top - (top_row * base_cell_size)
        if dist_to_cell_edge >= abs(dy) then
            player.y += dy
        else
            player.y -= dist_to_cell_edge
            dy += dist_to_cell_edge

            -- see if we can continue moving
            can_move = true
            for col in all(cols) do
                coll = is_collidable(col, top_row-1)
                if coll then
                    can_move = false
                    break
                end
            end

            if can_move then
                player.y += dy
            end
        end
    end
end

-- convert pixel value to cell value
function to_cell(pixel, inclusive)
    if inclusive == nil then
        inclusive = false
    end

    if inclusive then
        return flr(pixel / base_cell_size)
    else
        return flr((pixel-1) / base_cell_size)
    end
end

function is_collidable(cell_x, cell_y)
    return fget(mget(cell_x, cell_y), 0)
end

function reset()
    player.x = level.startx
    player.y = level.starty
end

function draw_objects()
    box_sprite = 5
    for box in all(level.boxes) do
        if box.touched then
            add_to_map(box.x, box.y, 64)
        else
            add_to_map(box.x, box.y, box_sprite)
        end
    end

    -- bigh
    add_to_map(1, 25, 7, 8)

    orb_sprite = 35
    for orb in all(level.orbs) do
        if orb.touched then
            add_to_map(orb.x, orb.y, 66)
        else
            add_to_map(orb.x, orb.y, orb_sprite)
        end
    end

    sign_sprite = 37
    for sign in all(level.signs) do
        add_to_map(sign.x, sign.y, sign_sprite)
    end
end

-- wrapped mset to dedupe code and handle large-scale sprites
function add_to_map(x, y, sprite, scale)
    if scale == nil then
        scale = spritescale
    end

    for r=0, scale-1 do
        for c=0, scale-1 do
            mset(spritescale * x + (c),
                 spritescale * y + (r),
                 sprite + c + (r * sprites_per_row))
        end
    end
end

function camera_relative_top_left()
    return camera_obj.x + camera_offset + -1 * cell_size * 4,
    camera_obj.y + camera_offset + -1 * cell_size * 4
end

function draw_debug()
    if (level.debug) then
        x, y = camera_relative_top_left()
        y += 5 * cell_size
        local off_y = 0

        for entry in all(debug_table.kv_sequence) do
            local res = entry.k..": "..tostr(entry.v)
            print(res, x, y + off_y, 9)

            off_y += base_cell_size
        end
    end
end

function draw_map()
    map(level.mapx, level.mapy, 0, 0, 128 * cell_size, 128 * cell_size)
end

-- draw player at correct position.
function draw_player()
    update_camera_pos()
    camera(camera_obj.x, camera_obj.y)
    spr(player.sprite, player.x, player.y, spritescale, spritescale, player.flipped)
end

-- helper stuff around debug table
function debug_update(k, v)
    local i = debug_table.index_lookup[k]
    if i == nil then
        add(debug_table.kv_sequence, {k=k, v=v})
        debug_table.index_lookup[k] = #debug_table.kv_sequence
    else
        debug_table.kv_sequence[i] = {k=k, v=v}
    end
end

-- more generic helpers
function str_replace(str, target, replacement)
    sub_index = 1
    for i=1, #str do
        if sub(str, i, i) == sub(target, sub_index, sub_index) then
            sub_index += 1

        -- this isn't the target, reset
        elseif sub_index > 1 then
            sub_index = 1
        end

        -- perform replace
        if sub_index > #target then
            return sub(str, 1, i - #target) .. replacement .. sub(str, i+1, #str)
        end
    end

    -- unable to replace
    return str
end

function str_mult_replace(str, variables)
    for key, value in pairs(variables) do
        str = str_replace(str, "${" .. key .. "}", value)
    end

    return str
end

-- pico8 necessary methods
function _update60()
    if is_menu then
        update_menu()
    elseif is_done then
        move_credits()
    else
        update_vv()
        move_player()
    end
end

function _draw()
    cls()
    if is_menu then
        draw_menu()
    elseif is_done then
        draw_credits()
    else
        draw_map()
        draw_player()
        draw_objects()
        draw_sign()
    end
    draw_debug()
end

function _init()
    cls()

    -- editor limitations
    sprites_per_row = 16

    -- our worlds stats
    base_cell_size = 8
    cell_size = 16
    spritescale = flr(cell_size / base_cell_size)

    -- state vars, for different screens
    is_menu = true
    is_done = false

    camera_offset = cell_size * 4
    textbox_offset = -camera_offset

    -- flag reference
    -- 0 collision
    -- 1 exit
    -- 2
    -- 3
    -- 4
    -- 5
    -- 6
    -- 7

    -- menu init
    menu = {
    }

    -- level init
    level = {
        startx = 7 * cell_size,
        starty = 14 * cell_size,
        sign_open = false,
        last_sign_text = "",
        grav_acc = 0.2,
        mapx = 0,
        mapy = 0,
        debug = false,

        -- these coordinates in cell_size cells
        -- TODO text wrapping (a gigantic pain)
        signs = {
            {
                x = 11,
                y = 14,
                text = "nothing important here",
            },
            {
                x = 12,
                y = 26,
                text = "(O) + (X) reset\nposition to start\n(O) to close\nthese messages",
            },
            {
                x = 9,
                y = 28,
                text = "touch boxes with (O)",
            },
            {
                x = 3,
                y = 24,
                text = "this is a bigh box",
            },
            {
                x = 44,
                y = 30,
                text = "you have touched\n${box_touch_count}\nblocks",
                is_dynamic = true,
                vars = {
                    box_touch_count = 0,
                },
            },
            {
                x = 49,
                y = 30,
                text = "you have touched\n${orb_touch_count}\nORBS",
                is_dynamic = true,
                vars = {
                    orb_touch_count = 0,
                },
            },
            {
                x = 34,
                y = 30,
                text = "you can also touch\nORBS\nwith (O)",
            },
            {
                x = 17,
                y = 15,
                text = "CONGRATS ON GETTING\nUP HERE!\nIT'S TRICKY!",
            },
        },
        orbs = {
            {
                x = 33,
                y = 30,
                touched = false,
            },
        },
        boxes = {
            {
                x = 11,
                y = 26,
            },
            {
                x = 6,
                y = 28,
            },
            {
                x = 5,
                y = 28,
            },
            {
                x = 5,
                y = 27,
            },
            {
                x = 16,
                y = 28,
            },
            {
                x = 24,
                y = 15,
            },
            {
                x = 25,
                y = 15,
            },
            {
                x = 26,
                y = 15,
            },
            {
                x = 27,
                y = 15,
            },
            {
                x = 20,
                y = 15,
            },
            {
                x = 19,
                y = 15,
            },
            {
                x = 24,
                y = 30,
            },
            {
                x = 25,
                y = 30,
            },
            {
                x = 26,
                y = 30,
            },
            {
                x = 27,
                y = 30,
            },
            {
                x = 28,
                y = 30,
            },
        },
    }

    -- player init
    player = {
        height = cell_size,
        width = cell_size - 2,
        jump_started = false,
        jump_locked = false,
        jump_frames = 0,
        max_jump_frames = 10,
        move_speed = 2,
        vv = 0,
        term_v = 2,
        jump_acc = -0.5,
        acc = 0,
        sprite = 33,
        flipped = false,
    }
    reset()

    -- camera init
    camera_obj = {
        x = player.x - camera_offset,
        y = player.y - camera_offset,
    }

    -- debug table init
    debug_table = {
        index_lookup = {},
        kv_sequence = {}
    }

    credits = {
        text = "you did it!\npress (O) to restart!\n(you can also move these " ..
        "\ncredits around with the arrows)" ..
        "\n\n\n\n\n\n\n\n\n\n\n\nmade by alixnovosi",
    }
end
__gfx__
00000000556666666666665500000000000000000555555555555550000005555555555555555555555555555555555555555555555555555550000000000000
00000000555666555566655500003333333300005566666666666655000005555555555555555555555555555555555555555555555555555550000000000000
007007006555655dd556555600037777777730005655555555555565000005555555555555555555555555555555555555555555555555555550000000000000
00077000665555dddd55556600377777777773005656656656656565000005555555555555555555555555555555555555555555555555555550000000000000
0007700066655dddddd5566603777777777777305656665656656565000005555555555555555555555555555555555555555555555555555550000000000000
007007006655dddddddd5566037766677676773056556665566565655555555555dddddddddddddddddddddddddddddddddddddddddddd555555555500000000
00000000655dddddddddd556037767777767773056555666566565655555555555dddddddddddddddddddddddddddddddddddddddddddd555555555500000000
0000000065dddddddddddd56037766777767773056565566656565655555555555dddddddddddddddddddddddddddddddddddddddddddd555555555500000000
0555555065dddddddddddd56037767777767773056566556665565655555555555dddddddddddddddddddddddddddddddddddddddddddd555555555500000000
56656665655dddddddddd556037766677676773056566555666565655555555555dddddddddddddddddddddddddddddddddddddddddddd555555555500000000
566656656655dddddddd55660377777777777730565665655666556555555dddddddddddddddddddddddddddddddddddddddddddddddddddddd5555500000000
5566656566655dddddd556660377666776667730565665665566656555555dddddddddddddddddddddddddddddddddddddddddddddddddddddd5555500000000
56566655665555dddd5555660377767777677730565665665556656555555dddddddddddddddddddddddddddddddddddddddddddddddddddddd5555500000000
566566656555655dd55655560377767777677730565555555555556555555dddddddddddddddddddddddddddddddddddddddddddddddddddddd5555500000000
5666566555566655556665550377767777677730556666666666665555555dddddd666666666666666dd666666666666666dd666666666666665555500000000
0555555055666666666666550377666777677730055555555555555055555dddddd666666666666666dd666666666666666dd666666666666665555500000000
0000000000000333333000000000055555000000055555555555555055555dddddd666666666666666dd666666666666666dd666666666666665555500000000
0000000000033666666330000005566667770000566666666666666555555dddddd666666666666666dd666666666666666dd666666666666665555500000000
0000000000366666666663000056666677777000565555555555556555555dddddd666666666666666dd666666666666666dd666666666666665555500000000
0000000003666666666666300566666677777700565666666666656555555dddddd66666ddddd66666ddddddd66666ddddddd66666ddddddddd5555500000000
0000000003663366663366300566666677777770565555555555556555555dddddd66666ddddd66666ddddddd66666ddddddd66666ddddddddd5555500000000
0000000036663366663366635666666677777770565666666666656555555dddddd66666ddddd66666ddddddd66666ddddddd66666ddddddddd5555500000000
0000000036666666666666635666666667777775565555555555556555555dddddd66666ddddd66666ddddddd66666ddddddd66666ddddddddd5555500000000
0000000036666666666666635666666666677765565555555555556555555dddddd66666ddddd66666ddddddd66666ddddddd66666ddddddddd5555500000000
0000000036666666666666635666666666666665566666666666666555555dddddd66666666666666dddddddd66666ddddddd66666ddddddddd5555500000000
0000000036663666666366635666666666666665055555555555555055555dddddd66666666666666dddddddd66666ddddddd66666dd66666666555500000000
0000000036663366663366635666666666666665000000055000000055555dddddd66666666666666dddddddd66666ddddddd66666dd66666666555500000000
0000000003666333333666300566666666666650000000055000000055555dddddd66666666666666dddddddd66666ddddddd66666dd66666666555500000000
0000000003666633336666300566666666666650000000055000000055555dddddd66666666666666dddddddd66666ddddddd66666dd66666666555500000000
0000000000366666666663000056666666666500000000055000000055555dddddd66666ddddd66666ddddddd66666ddddddd66666dd66666666555500000000
0000000000033666666330000005566666655000000000055000000055555dddddd66666ddddd66666ddddddd66666ddddddd66666ddddd66666555500000000
0000000000000333333000000000055555500000000000055000000055555dddddd66666ddddd66666ddddddd66666ddddddd66666ddddd66666555500000000
0333333333333330000003333300000000000000000000000000000055555dddddd66666ddddd66666ddddddd66666ddddddd66666ddddd66666555500000000
3366666666666633000336666777000000000000000000000000000055555dddddd66666ddddd66666ddddddd66666ddddddd66666ddddd66666555500000000
3655555555555563003666667777700000000000000000000000000055555dddddd666666666666666dd666666666666666dd666666666666666555500000000
3656656656656563036666667777770000000000000000000000000055555dddddd666666666666666dd666666666666666dd666666666666666555500000000
3656665656656563036666667777777000000000000000000000000055555dddddd666666666666666dd666666666666666dd666666666666666555500000000
3655666556656563366666667777777000000000000000000000000055555dddddd666666666666666dd666666666666666dd666666666666666555500000000
3655566656656563366666666777777300000000000000000000000055555dddddd666666666666666dd666666666666666dd666666666666666555500000000
3656556665656563366666666667776300000000000000000000000055555dddddddddddddddddddddddddddddddddddddddddddddddddddddd5555500000000
3656655666556563366666666666666300000000000000000000000055555dddddddddddddddddddddddddddddddddddddddddddddddddddddd5555500000000
3656655566656563366666666666666300000000000000000000000055555dddddddddddddddddddddddddddddddddddddddddddddddddddddd5555500000000
3656656556665563366666666666666300000000000000000000000055555dddddddddddddddddddddddddddddddddddddddddddddddddddddd5555500000000
3656656655666563036666666666663000000000000000000000000055555dddddddddddddd666666666dd666666666dd666ddd666ddddddddd5555500000000
3656656655566563036666666666663000000000000000000000000055555dddddddddddddd666666666dd666666666dd666ddd666ddddddddd5555500000000
3655555555555563003666666666630000000000000000000000000055555dddddddddddddd666666666dd666666666dd666ddd666ddddddddd5555500000000
3366666666666633000336666663300000000000000000000000000055555dddddddddddddd666ddd666dd666ddd666ddddd666dddddddddddd5555500000000
0333333333333330000003333330000000000000000000000000000055555dddddddddddddd666ddd666dd666ddd666ddddd666dddddddddddd5555500000000
0000000000000000000000000000000000000000000000000000000055555dddddddddddddd666ddd666dd666ddd666ddddd666dddddddddddd5555500000000
0000000000000000000000000000000000000000000000000000000055555dddddddddddddd66666666ddd666ddd666ddddd666dddddddddddd5555500000000
0000000000000000000000000000000000000000000000000000000055555dddddddddddddd66666666ddd666ddd666ddddd666dddddddddddd5555500000000
0000000000000000000000000000000000000000000000000000000055555dddddddddddddd66666666ddd666ddd666ddddd666dddddddddddd5555500000000
0000000000000000000000000000000000000000000000000000000055555dddddddddddddd666ddd66ddd666ddd666ddddd666dddddddddddd5555500000000
0000000000000000000000000000000000000000000000000000000055555dddddddddddddd666ddd666dd666ddd666ddddd666dddddddddddd5555500000000
000000000000000000000000000000000000000000000000000000005555555555ddddddddd666ddd666dd666ddd666ddddd666ddddddd555555555500000000
000000000000000000000000000000000000000000000000000000005555555555ddddddddd666666666dd666666666dd666ddd666dddd555555555500000000
000000000000000000000000000000000000000000000000000000005555555555ddddddddd666666666dd666666666dd666ddd666dddd555555555500000000
000000000000000000000000000000000000000000000000000000005555555555ddddddddd666666666dd666666666dd666ddd666dddd555555555500000000
000000000000000000000000000000000000000000000000000000005555555555dddddddddddddddddddddddddddddddddddddddddddd555555555500000000
00000000000000000000000000000000000000000000000000000000000005555555555555555555555555555555555555555555555555555550000000000000
00000000000000000000000000000000000000000000000000000000000005555555555555555555555555555555555555555555555555555550000000000000
00000000000000000000000000000000000000000000000000000000000005555555555555555555555555555555555555555555555555555550000000000000
00000000000000000000000000000000000000000000000000000000000005555555555555555555555555555555555555555555555555555550000000000000
00000000000000000000000000000000000000000000000000000000000005555555555555555555555555555555555555555555555555555550000000000000
00000000000000000000000000001020000000000000102000000000000010201020102010201020102000000000000010201020102010201020000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000001121000000000000112100000000000011211121112111211121112100000000000011211121112111211121000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000001020000000000000102000000000000000000000000000001020000000000000102010200000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000001121000000000000112100000000000000000000000000001121000000000000112111210000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000001020000000000000102000000000000000000000000000001020102000000000000010200000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000001121000000000000112100000000000000000000000000001121112100000000000011210000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000001020000000000000102000000000000000000000000000001020000000000000102010200000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000001121000000000000112100000000000000000000000000001121000000000000112111210000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000001020000000000000102000000000000000000000000000001020102000000000000010200000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000001121000000000000112100000000000000000000000000001121112100000000000011210000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
10201020102010201020102010201020000000000000102010201020102010201020102010201020000000000000102010201020102010201020102010201020
10201020102010201020102010201020102010201020102010201020102010201020102010201020000000000000000000000000000000000000000000000000
11211121112111211121112111211121000000000000112111211121112111211121112111211121000000000000112111211121112111211121112111211121
11211121112111211121112111211121112111211121112111211121112111211121112111211121000000000000000000000000000000000000000000000000
10200000000000000000000000000000000000000000000000001020000000000000000010201020102000000000000010200000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000010201020000000000000000000000000000000000000000000000000
11210000000000000000000000000000000000000000000000001121000000000000000011211121112100000000000011210000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000011211121000000000000000000000000000000000000000000000000
10200000000000000000000000000000000000000000000000001020000000000000000000001020000000000000102010200000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000001020000000000000000000000000000000000000000000000000
11210000000000000000000000000000000000000000000000001121000000000000000000001121000000000000112111210000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000001121000000000000000000000000000000000000000000000000
10200000000000000000000000000000000000000000000000000000000000000000000000001020102000000000000000000000000000000000000000000000
00000000000000000000102010200000000000000000000000000000000000000000000000001020000000000000000000000000000000000000000000000000
11210000000000000000000000000000000000000000000000000000000000000000000000001121112100000000000000000000000000000000000000000000
00000000000000000000112111210000000000000000000000000000000000000000000000001121000000000000000000000000000000000000000000000000
10200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000001020102000001020000000000000000000000000000000000000000000001020000000000000000000000000000000000000000000000000
11210000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000001121112100001121000000000000000000000000000000000000000000001121000000000000000000000000000000000000000000000000
10200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000102000000000000000000000000000000000
00000000000010201020102000000000102000000000000000000000000000000000000000001020000000000000000000000000000000000000000000000000
11210000000000000000000000000000000000000000000000000000000000000000000000000000000000000000112100000000000000000000000000000000
00000000000011211121112100000000112100000000000000000000000000000000000000001121000000000000000000000000000000000000000000000000
10200000000000000000000000000000000000000000102010201020000000000000000000000000000000001020102010200000000000000000000000000000
00000000102010201020102000000000000010200000000000000000000000000000000000001020000000000000000000000000000000000000000000000000
11210000000000000000000000000000000000000000112111211121000000000000000000000000000000001121112111210000000000000000000000000000
00000000112111211121112100000000000011210000000000000000000000000000000000001121000000000000000000000000000000000000000000000000
10200000000000000000000000000000000000001020102010201020102000000000000000000000000010201020102010201020000000000000000000000000
00001020102010201020102000000000000000001020000000000000000000000000000000001020000000000000000000000000000000000000000000000000
11210000000000000000000000000000000000001121112111211121112100000000000000000000000011211121112111211121000000000000000000000000
00001121112111211121112100000000000000001121000000000000000000000000000000001121000000000000000000000000000000000000000000000000
10201020102010201020102010201020102010201020102010201020102010201020102010201020102010201020102010201020102010201020000000000000
10201020102010201020102010200000000000000000102000000000000000000000000000001020000000000000000000000000000000000000000000000000
11211121112111211121112111211121112111211121112111211121112111211121112111211121112111211121112111211121112111211121000000000000
11211121112111211121112111210000000000000000112100000000000000000000000000001121000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000102000000000000000000000000000000000
00000000000000000000102010201020304000000000000000000000000000000000000010201020000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000112100000000000000000000000000000000
00000000000000000000112111211121314100000000000000000000000000000000000011211121000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000102010201020102010201020102010201020
10201020102010201020102010201020102010201020102010201020102010201020102010201020000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000112111211121112111211121112111211121
11211121112111211121112111211121112111211121112111211121112111211121112111211121000000000000000000000000000000000000000000000000
__label__
dddddd66666666dddddddd66666666dddddddd66666666dddddddd66666666dddddddd66666666dddddddd66666666dddddddd66666666000000000000000000
dddddd66666666dddddddd66666666dddddddd66666666dddddddd66666666dddddddd66666666dddddddd66666666dddddddd66666666000000000000000000
666666dddddddd0000000000000000000000000000000000000000000000000000000000000000044444444444444066666666dddddddd000000000000000000
666666dddddddd0000000000000000000000000000000000000000000000000000000000000000449999999999994466666666dddddddd000000000000000000
666666dddddddd0000000000000000000000000000000000000000000000000000000000000000494444444444449466666666dddddddd000000000000000000
666666dddddddd0000000000000000000000000000000000000000000000000000000000000000494994994994949466666666dddddddd000000000000000000
666666dddddddd0000000000000000000000000000000000000000000000000000000000000000494999494994949466666666dddddddd000000000000000000
666666dddddddd0000000000000000000000000000000000000000000000000000000000000000494499944994949466666666dddddddd000000000000000000
666666dddddddd0000000000000000000000000000000000000000000000000000000000000000494449994994949466666666dddddddd000000000000000000
666666dddddddd0000000000000000000000000000000000000000000000000000000000000000494944999494949466666666dddddddd000000000000000000
dddddd6666666600000000000000000000000000000000000000000000000000000000000000004949944999449494dddddddd66666666000000000000000000
dddddd6666666600000000000000000000000000000000000000000000000000000000000000004949944499949494dddddddd66666666000000000000000000
dddddd6666666600000000000000000000000000000000000000000000000000000000000000004949949449994494dddddddd66666666000000000000000000
dddddd6666666600000000000000000000000000000000000000000000000000000000000000004949949944999494dddddddd66666666000000000000000000
dddddd6666666600000000000000000000000000000000000000000000000000000000000000004949949944499494dddddddd66666666000000000000000000
dddddd6666666600000000000000000000000000000000000000000000000000000000000000004944444444444494dddddddd66666666000000000000000000
dddddd6666666600000000000000000000000000000000000000000000000000000000000000004499999999999944dddddddd66666666000000000000000000
dddddd6666666600000000000000000000000000000000000000000000000000000000000000000444444444444440dddddddd66666666000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000044444444444444066666666dddddddd000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000449999999999994466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000494444444444449466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000494994994994949466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000494999494994949466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000494499944994949466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000494449994994949466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000494944999494949466666666dddddddd000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000004949944999449494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000004949944499949494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000004949949449994494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000004949949944999494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000004949949944499494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000004944444444444494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000004499999999999944dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000444444444444440dddddddd66666666000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000044444444444444066666666dddddddd000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000449999999999994466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000494444444444449466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000494994994994949466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000494999494994949466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000494499944994949466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000494449994994949466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000494944999494949466666666dddddddd000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000004949944999449494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000004949944499949494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000004949949449994494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000004949949944999494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000004949949944499494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000004944444444444494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000004499999999999944dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000444444444444440dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000033330066666666dddddddd66666666dddddddd66666666dddddddd000000000000000000
0000000000000000000000000000000000000000000000000000000333633066666666dddddddd66666666dddddddd66666666dddddddd000000000000000000
0000000000000000000000000000000000000000000000000000000336666066666666dddddddd66666666dddddddd66666666dddddddd000000000000000000
0000000000000000000000000000000000000000000000000000000663636066666666dddddddd66666666dddddddd66666666dddddddd000000000000000000
0000000000000000000000000000000000000000000000000000000366666066666666dddddddd66666666dddddddd66666666dddddddd000000000000000000
0000000000000000000000000000000000000000000000000000000506600066666666dddddddd66666666dddddddd66666666dddddddd000000000000000000
0000000000000000000000000000000000000000000000000000003001100066666666dddddddd66666666dddddddd66666666dddddddd000000000000000000
0000000000000000000000000000000000000000000000000000003011110066666666dddddddd66666666dddddddd66666666dddddddd000000000000000000
00000000000000000000000000000000000000000000000000000001111110dddddddd66666666dddddddd66666666dddddddd66666666000000000000000000
00000000000000000000000000000000000000000000000000000006111160dddddddd66666666dddddddd66666666dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000000000000d1111d0dddddddd66666666dddddddd66666666dddddddd66666666000000000000000000
00000000000000000000000000000000000000000000000000000006555560dddddddd66666666dddddddd66666666dddddddd66666666000000000000000000
00000000000000000000000000000000000000000000000000000000500500dddddddd66666666dddddddd66666666dddddddd66666666000000000000000000
00000000000000000000000000000000000000000000000000000000500500dddddddd66666666dddddddd66666666dddddddd66666666000000000000000000
00000000000000000000000000000000000000000000000000000000500500dddddddd66666666dddddddd66666666dddddddd66666666000000000000000000
00000000000000000000000000000000000000000000000000000000600600dddddddd66666666dddddddd66666666dddddddd66666666000000000000000000
000000000000000000000000000000000000000000000004444444444444400444444444444440044444444444444066666666dddddddd000000000000000000
000000000000000000000000000000000000000000000044999999999999444499999999999944449999999999994466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000049444444444444944944444444444494494444444444449466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000049499499499494944949949949949494494994994994949466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000049499949499494944949994949949494494999494994949466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000049449994499494944944999449949494494499944994949466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000049444999499494944944499949949494494449994994949466666666dddddddd000000000000000000
000000000000000000000000000000000000000000000049494499949494944949449994949494494944999494949466666666dddddddd000000000000000000
0000000000000000000000000000000000000000000000494994499944949449499449994494944949944999449494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000494994449994949449499444999494944949944499949494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000494994944999449449499494499944944949949449994494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000494994994499949449499499449994944949949944999494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000494994994449949449499499444994944949949944499494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000494444444444449449444444444444944944444444444494dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000449999999999994444999999999999444499999999999944dddddddd66666666000000000000000000
0000000000000000000000000000000000000000000000044444444444444004444444444444400444444444444440dddddddd66666666000000000000000000
000000000000000000000000000000044444444444444004444444444444400444444444444440044444444444444066666666dddddddd000000000000000000
000000000000000000000000000000449999999999994444999999999999444499999999999944449999999999994466666666dddddddd000000000000000000
000000000000000000000000000000494444444444449449444444444444944944444444444494494444444444449466666666dddddddd000000000000000000
000000000000000000000000000000494994994994949449499499499494944949949949949494494994994994949466666666dddddddd000000000000000000
000000000000000000000000000000494999494994949449499949499494944949994949949494494999494994949466666666dddddddd000000000000000000
000000000000000000000000000000494499944994949449449994499494944944999449949494494499944994949466666666dddddddd000000000000000000
000000000000000000000000000000494449994994949449444999499494944944499949949494494449994994949466666666dddddddd000000000000000000
000000000000000000000000000000494944999494949449494499949494944949449994949494494944999494949466666666dddddddd000000000000000000
0000000000000000000000000000004949944999449494494994499944949449499449994494944949944999449494dddddddd66666666000000000000000000
0000000000000000000000000000004949944499949494494994449994949449499444999494944949944499949494dddddddd66666666000000000000000000
0000000000000000000000000000004949949449994494494994944999449449499494499944944949949449994494dddddddd66666666000000000000000000
0000000000000000000000000000004949949944999494494994994499949449499499449994944949949944999494dddddddd66666666000000000000000000
0000000000000000000000000000004949949944499494494994994449949449499499444994944949949944499494dddddddd66666666000000000000000000
0000000000000000000000000000004944444444444494494444444444449449444444444444944944444444444494dddddddd66666666000000000000000000
0000000000000000000000000000004499999999999944449999999999994444999999999999444499999999999944dddddddd66666666000000000000000000
0000000000000000000000000000000444444444444440044444444444444004444444444444400444444444444440dddddddd66666666000000000000000000
000000000000000444444444444440044444444444444004444444444444400444444444444440044444444444444066666666dddddddd000000000000000000
000000000000004499999999999944449999999999994444999999999999444499999999999944449999999999994466666666dddddddd000000000000000000
000000000000004944444444444494494444444444449449444444444444944944444444444494494444444444449466666666dddddddd000000000000000000
000000000000004949949949949494494994994994949449499499499494944949949949949494494994994994949466666666dddddddd000000000000000000
000000000000004949994949949494494999494994949449499949499494944949994949949494494999494994949466666666dddddddd000000000000000000
000000000000004944999449949494494499944994949449449994499494944944999449949494494499944994949466666666dddddddd000000000000000000
000000000000004944499949949494494449994994949449444999499494944944499949949494494449994994949466666666dddddddd000000000000000000
000000000000004949449994949494494944999494949449494499949494944949449994949494494944999494949466666666dddddddd000000000000000000
0000000000000049499449994494944949944999449494494994499944949449499449994494944949944999449494dddddddd66666666000000000000000000
0000000000000049499444999494944949944499949494494994449994949449499444999494944949944499949494dddddddd66666666000000000000000000
0000000000000049499494499944944949949449994494494994944999449449499494499944944949949449994494dddddddd66666666000000000000000000
0000000000000049499499449994944949949944999494494994994499949449499499449994944949949944999494dddddddd66666666000000000000000000
0000000000000049499499444994944949949944499494494994994449949449499499444994944949949944499494dddddddd66666666000000000000000000
0000000000000049444444444444944944444444444494494444444444449449444444444444944944444444444494dddddddd66666666000000000000000000
0000000000000044999999999999444499999999999944449999999999994444999999999999444499999999999944dddddddd66666666000000000000000000
0000000000000004444444444444400444444444444440044444444444444004444444444444400444444444444440dddddddd66666666000000000000000000
444444444444400444444444444440044444444444444004444444444444400444444444444440044444444444444066666666dddddddd000000000000000000
999999999999444499999999999944449999999999994444999999999999444499999999999944449999999999994466666666dddddddd000000000000000000
444444444444944944444444444494494444444444449449444444444444944944444444444494494444444444449466666666dddddddd000000000000000000
499499499494944949949949949494494994994994949449499499499494944949949949949494494994994994949466666666dddddddd000000000000000000
499949499494944949994949949494494999494994949449499949499494944949994949949494494999494994949466666666dddddddd000000000000000000
449994499494944944999449949494494499944994949449449994499494944944999449949494494499944994949466666666dddddddd000000000000000000
444999499494944944499949949494494449994994949449444999499494944944499949949494494449994994949466666666dddddddd000000000000000000
494499949494944949449994949494494944999494949449494499949494944949449994949494494944999494949466666666dddddddd000000000000000000
4994499944949449499449994494944949944999449494494994499944949449499449994494944949944999449494dddddddd66666666000000000000000000
4994449994949449499444999494944949944499949494494994449994949449499444999494944949944499949494dddddddd66666666000000000000000000
4994944999449449499494499944944949949449994494494994944999449449499494499944944949949449994494dddddddd66666666000000000000000000
4994994499949449499499449994944949949944999494494994994499949449499499449994944949949944999494dddddddd66666666000000000000000000
4994994449949449499499444994944949949944499494494994994449949449499499444994944949949944499494dddddddd66666666000000000000000000
4444444444449449444444444444944944444444444494494444444444449449444444444444944944444444444494dddddddd66666666000000000000000000

__gff__
0001010202050501010101010101010000010102020505010101010101010100000000000000000100000000000b01000000000000000000000000000000010005050000000000010000000000000100050500000000000100000000000001000000000000000001000000000000010000000000000000010101010101010100
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000002f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000002f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000003f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000002f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000102010201020102010201020102010201020102010201020102010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000001112111211121112111211121112111211121112111211121112111200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000102000000000000000000000000000000000000000000000000010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000001112000000000000000000000000000000000000000000000000111200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000102010201020102010201020102000000000102000000000000000000000000000000000000000000000000010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000001112111211121112111211121112000000001112000000000000000000000000000000000000000000000000111200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000102000000000000000000000102000000000102000000000000000000000000000000000000000000000000010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000001112000000000000000000001112000000001112000000000000000000000000000000000000000000000000111200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000102000000000000000000000102000000000102000000000000000000000000000000000000000000000000010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000001112000000000000000000001112000000001112000000000000000000000000000000000000000000000000111200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000102000000000000000000000102000000000102000000000000000000000000000000000000000000000000010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000001112000000000000000000001112000000001112000000000000000000000000000000000000000000000000111200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000102000000000000000000000102000000000102000000000000000000000000000000000000000000000000010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000001112000000000000000000001112000000001112000000000000000000000000000000000000000000000000111200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000102010200000000000001020102000000000102000000000000000000000000000000000000000000000000010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000001112111200000000000011121112000000001112000000000000000000000000000000000000000000000000111200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
011801011b050270200302003020030200302003020030200302003020030201b0502702003020030200302003020030200302003020030201b0502702003020030201b050270200302003020030200302003020
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000
00 00000000

