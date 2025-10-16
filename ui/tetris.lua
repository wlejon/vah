-- Tetris Game Implementation in Lua
-- Uses NanoVG for rendering on ElementCanvas

-- Game constants
local COLS = 10
local ROWS = 20
local BLOCK_SIZE = 25
local PREVIEW_SIZE = 4

-- Colors for each tetromino type (Tetris pieces)
local COLORS = {
    I = nvg.rgba(0, 240, 240, 255),    -- Cyan
    O = nvg.rgba(240, 240, 0, 255),    -- Yellow
    T = nvg.rgba(160, 0, 240, 255),    -- Purple
    S = nvg.rgba(0, 240, 0, 255),      -- Green
    Z = nvg.rgba(240, 0, 0, 255),      -- Red
    J = nvg.rgba(0, 0, 240, 255),      -- Blue
    L = nvg.rgba(240, 160, 0, 255),    -- Orange
    EMPTY = nvg.rgba(30, 30, 40, 255), -- Dark background
    GRID = nvg.rgba(50, 50, 60, 255),  -- Grid lines
    GHOST = nvg.rgba(100, 100, 120, 100) -- Ghost piece
}

-- Tetromino shapes (4x4 grid representations)
local SHAPES = {
    I = {
        {0, 0, 0, 0},
        {1, 1, 1, 1},
        {0, 0, 0, 0},
        {0, 0, 0, 0}
    },
    O = {
        {0, 0, 0, 0},
        {0, 1, 1, 0},
        {0, 1, 1, 0},
        {0, 0, 0, 0}
    },
    T = {
        {0, 0, 0, 0},
        {0, 1, 0, 0},
        {1, 1, 1, 0},
        {0, 0, 0, 0}
    },
    S = {
        {0, 0, 0, 0},
        {0, 1, 1, 0},
        {1, 1, 0, 0},
        {0, 0, 0, 0}
    },
    Z = {
        {0, 0, 0, 0},
        {1, 1, 0, 0},
        {0, 1, 1, 0},
        {0, 0, 0, 0}
    },
    J = {
        {0, 0, 0, 0},
        {1, 0, 0, 0},
        {1, 1, 1, 0},
        {0, 0, 0, 0}
    },
    L = {
        {0, 0, 0, 0},
        {0, 0, 1, 0},
        {1, 1, 1, 0},
        {0, 0, 0, 0}
    }
}

local SHAPE_TYPES = {"I", "O", "T", "S", "Z", "J", "L"}

-- Game state
local game = {
    board = {},
    current_piece = nil,
    current_type = nil,
    current_x = 0,
    current_y = 0,
    next_piece_type = nil,
    score = 0,
    lines = 0,
    level = 1,
    game_over = false,
    paused = false,
    last_fall = 0,
    fall_speed = 1.0,  -- Time in seconds between automatic piece falls
    keys_pressed = {}
}

-- Initialize the game board
local function init_board()
    game.board = {}
    for row = 1, ROWS do
        game.board[row] = {}
        for col = 1, COLS do
            game.board[row][col] = "EMPTY"
        end
    end
end

-- Get random tetromino type
local function get_random_piece()
    return SHAPE_TYPES[math.random(1, #SHAPE_TYPES)]
end

-- Create a deep copy of a shape matrix
local function copy_shape(shape)
    local copy = {}
    for i = 1, #shape do
        copy[i] = {}
        for j = 1, #shape[i] do
            copy[i][j] = shape[i][j]
        end
    end
    return copy
end

-- Rotate a piece 90 degrees clockwise
local function rotate_piece(shape)
    local n = #shape
    local rotated = {}
    for i = 1, n do
        rotated[i] = {}
        for j = 1, n do
            rotated[i][j] = shape[n - j + 1][i]
        end
    end
    return rotated
end

-- Check if a piece position is valid (no collision)
local function is_valid_position(piece, x, y)
    for row = 1, #piece do
        for col = 1, #piece[row] do
            if piece[row][col] == 1 then
                local board_x = x + col
                local board_y = y + row

                -- Check horizontal bounds
                if board_x < 1 or board_x > COLS then
                    return false
                end

                -- Check bottom bound
                if board_y > ROWS then
                    return false
                end

                -- Check collision with placed pieces (only for cells within board)
                if board_y >= 1 and board_y <= ROWS and
                   board_x >= 1 and board_x <= COLS and
                   game.board[board_y][board_x] ~= "EMPTY" then
                    return false
                end
            end
        end
    end
    return true
end

-- Lock the current piece into the board
-- Returns true if any block was placed above row 1 (game over condition)
local function lock_piece()
    local placed_above_board = false

    for row = 1, #game.current_piece do
        for col = 1, #game.current_piece[row] do
            if game.current_piece[row][col] == 1 then
                local board_x = game.current_x + col
                local board_y = game.current_y + row

                -- Check if block is above the visible board
                if board_y < 1 then
                    placed_above_board = true
                end

                -- Only place blocks that are within the board bounds
                if board_y >= 1 and board_y <= ROWS and
                   board_x >= 1 and board_x <= COLS then
                    game.board[board_y][board_x] = game.current_type
                end
            end
        end
    end

    return placed_above_board
end

-- Clear completed lines and return number cleared
local function clear_lines()
    local lines_cleared = 0
    local row = ROWS

    while row >= 1 do
        local line_full = true
        for col = 1, COLS do
            if game.board[row][col] == "EMPTY" then
                line_full = false
                break
            end
        end

        if line_full then
            -- Remove the line
            table.remove(game.board, row)
            -- Add new empty line at top
            local new_line = {}
            for col = 1, COLS do
                new_line[col] = "EMPTY"
            end
            table.insert(game.board, 1, new_line)
            lines_cleared = lines_cleared + 1
        else
            row = row - 1
        end
    end

    return lines_cleared
end

-- Spawn a new piece
local function spawn_piece()
    game.current_type = game.next_piece_type or get_random_piece()
    game.next_piece_type = get_random_piece()
    game.current_piece = copy_shape(SHAPES[game.current_type])
    game.current_x = math.floor(COLS / 2) - 1
    game.current_y = -1  -- Start above the board to allow partial spawning

    -- Check if the piece can spawn (game over if there's a collision immediately)
    -- We check if it can exist in its spawn position OR move down at least once
    if not is_valid_position(game.current_piece, game.current_x, game.current_y) and
       not is_valid_position(game.current_piece, game.current_x, game.current_y + 1) then
        game.game_over = true
    end
end

-- Move piece down
local function move_down()
    if is_valid_position(game.current_piece, game.current_x, game.current_y + 1) then
        game.current_y = game.current_y + 1
        return true
    else
        -- Lock piece and check for game over
        local placed_above = lock_piece()

        -- Game over if piece locked with blocks above the board
        if placed_above then
            game.game_over = true
            return false
        end

        local lines = clear_lines()

        -- Update score
        if lines > 0 then
            game.lines = game.lines + lines
            game.score = game.score + (lines * lines * 100 * game.level)

            -- Increase level every 10 lines
            game.level = math.floor(game.lines / 10) + 1
            game.fall_speed = math.max(0.1, 1.0 - (game.level - 1) * 0.05)
        end

        spawn_piece()
        return false
    end
end

-- Calculate ghost piece position (where piece will land)
local function get_ghost_position()
    local ghost_y = game.current_y
    while is_valid_position(game.current_piece, game.current_x, ghost_y + 1) do
        ghost_y = ghost_y + 1
    end
    return ghost_y
end

-- Hard drop (instant drop to bottom)
local function hard_drop()
    while move_down() do
        game.score = game.score + 2  -- Bonus points for hard drop
    end
end

-- Initialize game
local function init_game()
    init_board()
    game.score = 0
    game.lines = 0
    game.level = 1
    game.game_over = false
    game.paused = false
    game.last_fall = 0
    game.fall_speed = 1.0
    game.next_piece_type = get_random_piece()
    spawn_piece()
    math.randomseed(os.time())
end

-- Draw a single block
local function draw_block(nvg_ctx, x, y, color, size)
    -- Draw filled block
    nvg.beginPath(nvg_ctx)
    nvg.rect(nvg_ctx, x, y, size, size)
    nvg.fillColor(nvg_ctx, color)
    nvg.fill(nvg_ctx)

    -- Draw darker outline for contrast
    nvg.beginPath(nvg_ctx)
    nvg.rect(nvg_ctx, x, y, size, size)
    nvg.strokeWidth(nvg_ctx, 2.0)
    nvg.strokeColor(nvg_ctx, nvg.rgba(0, 0, 0, 180))
    nvg.stroke(nvg_ctx)

    -- Draw subtle inner highlight for depth effect
    nvg.beginPath(nvg_ctx)
    nvg.rect(nvg_ctx, x + 1, y + 1, size - 2, size - 2)
    nvg.strokeWidth(nvg_ctx, 1.0)
    nvg.strokeColor(nvg_ctx, nvg.rgba(255, 255, 255, 40))
    nvg.stroke(nvg_ctx)
end

-- Draw the game board
local function draw_board(nvg_ctx, offset_x, offset_y)
    -- Draw board background
    nvg.beginPath(nvg_ctx)
    nvg.rect(nvg_ctx, offset_x, offset_y, COLS * BLOCK_SIZE, ROWS * BLOCK_SIZE)
    nvg.fillColor(nvg_ctx, COLORS.EMPTY)
    nvg.fill(nvg_ctx)

    -- Draw grid lines
    for row = 0, ROWS do
        nvg.beginPath(nvg_ctx)
        nvg.moveTo(nvg_ctx, offset_x, offset_y + row * BLOCK_SIZE)
        nvg.lineTo(nvg_ctx, offset_x + COLS * BLOCK_SIZE, offset_y + row * BLOCK_SIZE)
        nvg.strokeWidth(nvg_ctx, 1.0)
        nvg.strokeColor(nvg_ctx, COLORS.GRID)
        nvg.stroke(nvg_ctx)
    end

    for col = 0, COLS do
        nvg.beginPath(nvg_ctx)
        nvg.moveTo(nvg_ctx, offset_x + col * BLOCK_SIZE, offset_y)
        nvg.lineTo(nvg_ctx, offset_x + col * BLOCK_SIZE, offset_y + ROWS * BLOCK_SIZE)
        nvg.strokeWidth(nvg_ctx, 1.0)
        nvg.strokeColor(nvg_ctx, COLORS.GRID)
        nvg.stroke(nvg_ctx)
    end

    -- Draw placed pieces
    for row = 1, ROWS do
        for col = 1, COLS do
            if game.board[row][col] ~= "EMPTY" then
                local block_x = offset_x + (col - 1) * BLOCK_SIZE
                local block_y = offset_y + (row - 1) * BLOCK_SIZE
                draw_block(nvg_ctx, block_x, block_y, COLORS[game.board[row][col]], BLOCK_SIZE)
            end
        end
    end

    -- Draw ghost piece
    if game.current_piece and not game.game_over then
        local ghost_y = get_ghost_position()
        for row = 1, #game.current_piece do
            for col = 1, #game.current_piece[row] do
                if game.current_piece[row][col] == 1 then
                    local block_x = offset_x + (game.current_x + col - 1) * BLOCK_SIZE
                    local block_y = offset_y + (ghost_y + row - 1) * BLOCK_SIZE
                    draw_block(nvg_ctx, block_x, block_y, COLORS.GHOST, BLOCK_SIZE)
                end
            end
        end
    end

    -- Draw current piece
    if game.current_piece and not game.game_over then
        for row = 1, #game.current_piece do
            for col = 1, #game.current_piece[row] do
                if game.current_piece[row][col] == 1 then
                    local block_x = offset_x + (game.current_x + col - 1) * BLOCK_SIZE
                    local block_y = offset_y + (game.current_y + row - 1) * BLOCK_SIZE
                    draw_block(nvg_ctx, block_x, block_y, COLORS[game.current_type], BLOCK_SIZE)
                end
            end
        end
    end
end

-- Draw the next piece preview
local function draw_next_piece(nvg_ctx, x, y)
    local preview_size = PREVIEW_SIZE * BLOCK_SIZE

    -- Draw preview background
    nvg.beginPath(nvg_ctx)
    nvg.rect(nvg_ctx, x, y, preview_size, preview_size)
    nvg.fillColor(nvg_ctx, COLORS.EMPTY)
    nvg.fill(nvg_ctx)

    nvg.beginPath(nvg_ctx)
    nvg.rect(nvg_ctx, x, y, preview_size, preview_size)
    nvg.strokeWidth(nvg_ctx, 2.0)
    nvg.strokeColor(nvg_ctx, COLORS.GRID)
    nvg.stroke(nvg_ctx)

    -- Draw next piece
    if game.next_piece_type then
        local next_shape = SHAPES[game.next_piece_type]
        for row = 1, #next_shape do
            for col = 1, #next_shape[row] do
                if next_shape[row][col] == 1 then
                    local block_x = x + (col - 1) * BLOCK_SIZE
                    local block_y = y + (row - 1) * BLOCK_SIZE
                    draw_block(nvg_ctx, block_x, block_y, COLORS[game.next_piece_type], BLOCK_SIZE)
                end
            end
        end
    end
end

-- Main render function called by ElementCanvas
function render_tetris(nvg_ctx, x, y, w, h, time)
    -- Update game logic
    if not game.game_over and not game.paused then
        if time - game.last_fall >= game.fall_speed then
            move_down()
            game.last_fall = time
        end
    end

    -- Draw background
    nvg.beginPath(nvg_ctx)
    nvg.rect(nvg_ctx, x, y, w, h)
    nvg.fillColor(nvg_ctx, nvg.rgba(20, 20, 30, 255))
    nvg.fill(nvg_ctx)

    -- Calculate layout
    local board_width = COLS * BLOCK_SIZE
    local board_height = ROWS * BLOCK_SIZE
    local board_x = x + 20
    local board_y = y + 60
    local sidebar_x = board_x + board_width + 30

    -- Draw title
    nvg.fontSize(nvg_ctx, 32.0)
    nvg.fontFace(nvg_ctx, "roboto")
    nvg.textAlign(nvg_ctx, nvg.ALIGN_LEFT + nvg.ALIGN_TOP)
    nvg.fillColor(nvg_ctx, nvg.rgba(255, 255, 255, 255))
    nvg.text(nvg_ctx, x + 20, y + 10, "TETRIS")

    -- Draw game board
    draw_board(nvg_ctx, board_x, board_y)

    -- Draw sidebar info
    local info_y = board_y

    -- Next piece
    nvg.fontSize(nvg_ctx, 18.0)
    nvg.fillColor(nvg_ctx, nvg.rgba(200, 200, 200, 255))
    nvg.text(nvg_ctx, sidebar_x, info_y, "NEXT")
    info_y = info_y + 25
    draw_next_piece(nvg_ctx, sidebar_x, info_y)
    info_y = info_y + PREVIEW_SIZE * BLOCK_SIZE + 30

    -- Score
    nvg.fontSize(nvg_ctx, 18.0)
    nvg.fillColor(nvg_ctx, nvg.rgba(200, 200, 200, 255))
    nvg.text(nvg_ctx, sidebar_x, info_y, "SCORE")
    info_y = info_y + 25
    nvg.fontSize(nvg_ctx, 24.0)
    nvg.fillColor(nvg_ctx, nvg.rgba(255, 255, 255, 255))
    nvg.text(nvg_ctx, sidebar_x, info_y, tostring(game.score))
    info_y = info_y + 40

    -- Lines
    nvg.fontSize(nvg_ctx, 18.0)
    nvg.fillColor(nvg_ctx, nvg.rgba(200, 200, 200, 255))
    nvg.text(nvg_ctx, sidebar_x, info_y, "LINES")
    info_y = info_y + 25
    nvg.fontSize(nvg_ctx, 24.0)
    nvg.fillColor(nvg_ctx, nvg.rgba(255, 255, 255, 255))
    nvg.text(nvg_ctx, sidebar_x, info_y, tostring(game.lines))
    info_y = info_y + 40

    -- Level
    nvg.fontSize(nvg_ctx, 18.0)
    nvg.fillColor(nvg_ctx, nvg.rgba(200, 200, 200, 255))
    nvg.text(nvg_ctx, sidebar_x, info_y, "LEVEL")
    info_y = info_y + 25
    nvg.fontSize(nvg_ctx, 24.0)
    nvg.fillColor(nvg_ctx, nvg.rgba(255, 255, 255, 255))
    nvg.text(nvg_ctx, sidebar_x, info_y, tostring(game.level))
    info_y = info_y + 50

    -- Controls
    nvg.fontSize(nvg_ctx, 14.0)
    nvg.fillColor(nvg_ctx, nvg.rgba(150, 150, 150, 255))
    nvg.text(nvg_ctx, sidebar_x, info_y, "CONTROLS")
    info_y = info_y + 20
    nvg.fontSize(nvg_ctx, 12.0)
    nvg.fillColor(nvg_ctx, nvg.rgba(120, 120, 120, 255))
    nvg.text(nvg_ctx, sidebar_x, info_y, "A D Move")
    info_y = info_y + 16
    nvg.text(nvg_ctx, sidebar_x, info_y, "S Soft Drop")
    info_y = info_y + 16
    nvg.text(nvg_ctx, sidebar_x, info_y, "Left Click Rotate")
    info_y = info_y + 16
    nvg.text(nvg_ctx, sidebar_x, info_y, "W or SPACE Hard Drop")
    info_y = info_y + 16
    nvg.text(nvg_ctx, sidebar_x, info_y, "P Pause")
    info_y = info_y + 16
    nvg.text(nvg_ctx, sidebar_x, info_y, "C New Game")

    -- Game over overlay
    if game.game_over then
        nvg.beginPath(nvg_ctx)
        nvg.rect(nvg_ctx, board_x, board_y, board_width, board_height)
        nvg.fillColor(nvg_ctx, nvg.rgba(0, 0, 0, 180))
        nvg.fill(nvg_ctx)

        nvg.fontSize(nvg_ctx, 36.0)
        nvg.textAlign(nvg_ctx, nvg.ALIGN_CENTER + nvg.ALIGN_MIDDLE)
        nvg.fillColor(nvg_ctx, nvg.rgba(255, 50, 50, 255))
        nvg.text(nvg_ctx, board_x + board_width / 2, board_y + board_height / 2 - 20, "GAME OVER")

        nvg.fontSize(nvg_ctx, 16.0)
        nvg.fillColor(nvg_ctx, nvg.rgba(200, 200, 200, 255))
        nvg.text(nvg_ctx, board_x + board_width / 2, board_y + board_height / 2 + 20, "Press C to restart")
    end

    -- Pause overlay
    if game.paused and not game.game_over then
        nvg.beginPath(nvg_ctx)
        nvg.rect(nvg_ctx, board_x, board_y, board_width, board_height)
        nvg.fillColor(nvg_ctx, nvg.rgba(0, 0, 0, 180))
        nvg.fill(nvg_ctx)

        nvg.fontSize(nvg_ctx, 36.0)
        nvg.textAlign(nvg_ctx, nvg.ALIGN_CENTER + nvg.ALIGN_MIDDLE)
        nvg.fillColor(nvg_ctx, nvg.rgba(255, 255, 100, 255))
        nvg.text(nvg_ctx, board_x + board_width / 2, board_y + board_height / 2, "PAUSED")
    end
end

-- Mouse click handler for rotation (called only on button down/up, not during drag)
function handle_tetris_mouse(button, button_down, mouse_x, mouse_y, canvas_x, canvas_y)
    -- Only process left mouse button (0) down events
    if button ~= 0 or not button_down then
        return
    end

    -- Don't process if game over or paused
    if game.game_over or game.paused then
        return
    end

    -- Rotate piece on left click
    local rotated = rotate_piece(game.current_piece)
    if is_valid_position(rotated, game.current_x, game.current_y) then
        game.current_piece = rotated
    end
end

-- Key handler for game controls
function handle_tetris_key(key, key_down)
    -- Track key state for simultaneous input
    game.keys_pressed[key] = key_down

    -- Only process key down events for single-press actions
    if not key_down then
        return
    end

    -- Handle restart
    if key == "c" then
        init_game()
        return
    end

    -- Handle pause
    if key == "p" then
        game.paused = not game.paused
        return
    end

    -- Don't process game controls if game over or paused
    if game.game_over or game.paused then
        return
    end

    -- Movement (WASD)
    if key == "a" then
        if is_valid_position(game.current_piece, game.current_x - 1, game.current_y) then
            game.current_x = game.current_x - 1
        end
    elseif key == "d" then
        if is_valid_position(game.current_piece, game.current_x + 1, game.current_y) then
            game.current_x = game.current_x + 1
        end
    elseif key == "s" then
        move_down()
    elseif key == "w" or key == "space" then
        -- Hard drop
        hard_drop()
    end
end

-- Initialize game on load
init_game()
