-- Populate Tetris Code Flow
-- This represents the complete mechanical flow of the tetris game

-- Clear existing tetris data if any
DELETE FROM connections WHERE flow_id IN (SELECT id FROM flows WHERE app_name = 'tetris');
DELETE FROM nodes WHERE flow_id IN (SELECT id FROM flows WHERE app_name = 'tetris');
DELETE FROM node_types WHERE flow_id IN (SELECT id FROM flows WHERE app_name = 'tetris');
DELETE FROM flows WHERE app_name = 'tetris';

-- Create the flow entry
INSERT INTO flows (name, description, app_name) VALUES (
    'Tetris - Mechanical Code Flow',
    'Detailed mechanical view showing initialization, main loop, input handling, game logic branches, and rendering pipeline',
    'tetris'
);

-- Get the flow_id for subsequent inserts
-- In SQLite, we'll use last_insert_rowid() or reference by subquery

-- Node Types (with color coding by function type)
INSERT INTO node_types (flow_id, name, type, color_r, color_g, color_b, color_a, file_location, description, details) VALUES
-- 1: Initialization
((SELECT id FROM flows WHERE app_name = 'tetris'), 'init_game()', 'init', 100, 180, 255, 255,
 'ui/tetris.lua:286',
 'Entry point: Initializes game board (10x20), spawns first piece, sets score=0, level=1',
 'Called on script load and when ''C'' key pressed. Seeds RNG with os.time()'),

-- 2: Board init
((SELECT id FROM flows WHERE app_name = 'tetris'), 'init_board()', 'function', 120, 200, 255, 255,
 'ui/tetris.lua:91',
 'Creates 20x10 grid filled with ''EMPTY'' strings',
 '2D table structure: board[row][col]. Row 1 = top, Row 20 = bottom'),

-- 3: Spawn piece
((SELECT id FROM flows WHERE app_name = 'tetris'), 'spawn_piece()', 'function', 140, 220, 160, 255,
 'ui/tetris.lua:222',
 'Spawns new tetromino at top-center (x=4, y=-1) from 7 piece types',
 'Pieces: I, O, T, S, Z, J, L. Starts above board (y=-1) to allow partial spawn. Sets current_type, next_type'),

-- 4: Check spawn valid
((SELECT id FROM flows WHERE app_name = 'tetris'), 'Check Spawn Valid?', 'branch', 255, 200, 100, 255,
 'ui/tetris.lua:231-233',
 'BRANCH: Can piece exist at spawn position OR move down once?',
 'If both fail → game_over = true. This allows pieces to partially spawn'),

-- 5: Main loop
((SELECT id FROM flows WHERE app_name = 'tetris'), 'render_tetris()', 'loop', 200, 140, 220, 255,
 'ui/tetris.lua:421',
 'MAIN LOOP: Called ~60fps by ElementCanvas. Updates game state, then renders',
 'Receives NanoVG context, canvas bounds, current time. Single entry point for all rendering'),

-- 6: Check game state
((SELECT id FROM flows WHERE app_name = 'tetris'), 'Check Game State', 'branch', 255, 180, 120, 255,
 'ui/tetris.lua:423',
 'BRANCH: Is game active, paused, or over?',
 'if game_over → show overlay. if paused → show overlay. else → run game logic'),

-- 7: Check fall timer
((SELECT id FROM flows WHERE app_name = 'tetris'), 'Check Fall Timer', 'branch', 255, 220, 140, 255,
 'ui/tetris.lua:424-426',
 'BRANCH: Has fall_speed seconds elapsed since last fall?',
 'fall_speed starts at 1.0s, decreases by 0.05s per level (min 0.1s). time from canvas parameter'),

-- 8: Move down
((SELECT id FROM flows WHERE app_name = 'tetris'), 'move_down()', 'function', 120, 200, 140, 255,
 'ui/tetris.lua:238',
 'Attempts to move current piece down by 1 row',
 'Returns true if moved successfully, false if locked. Updates last_fall timer'),

-- 9: Collision check
((SELECT id FROM flows WHERE app_name = 'tetris'), 'is_valid_position()', 'function', 160, 140, 255, 255,
 'ui/tetris.lua:132',
 'Collision detection: Checks if piece at (x,y) is valid',
 'Iterates 4x4 shape matrix. Checks: bounds (x: 1-10, y: ≤20), collision with board. Returns bool'),

-- 10: Can move down branch
((SELECT id FROM flows WHERE app_name = 'tetris'), 'Check Can Move Down?', 'branch', 255, 180, 100, 255,
 'ui/tetris.lua:239',
 'BRANCH: Is (current_x, current_y + 1) valid?',
 'Yes → increment y. No → lock piece and check line clears'),

-- 11: Lock piece
((SELECT id FROM flows WHERE app_name = 'tetris'), 'lock_piece()', 'function', 200, 100, 100, 255,
 'ui/tetris.lua:163',
 'Writes current piece into board at its position',
 'Sets board[y][x] = current_type for each filled cell. Returns true if any block placed at y < 1'),

-- 12: Check placed above
((SELECT id FROM flows WHERE app_name = 'tetris'), 'Check Placed Above?', 'branch', 255, 120, 120, 255,
 'ui/tetris.lua:244-249',
 'BRANCH: Did piece lock with blocks above visible board?',
 'If yes → game_over = true, return. If no → continue to line clear check'),

-- 13: Clear lines
((SELECT id FROM flows WHERE app_name = 'tetris'), 'clear_lines()', 'function', 140, 200, 100, 255,
 'ui/tetris.lua:190',
 'Scans board bottom-up, removes full rows, adds empty rows at top',
 'Uses table.remove() and table.insert(). Returns number of lines cleared (0-4)'),

-- 14: Check lines cleared
((SELECT id FROM flows WHERE app_name = 'tetris'), 'Check Lines > 0?', 'branch', 255, 220, 100, 255,
 'ui/tetris.lua:255',
 'BRANCH: Were any lines cleared?',
 'If yes → update score and level. If no → just spawn next piece'),

-- 15: Update score
((SELECT id FROM flows WHERE app_name = 'tetris'), 'Update Score & Level', 'function', 180, 220, 120, 255,
 'ui/tetris.lua:256-261',
 'score += lines² × 100 × level. Level = floor(total_lines / 10) + 1',
 '1 line = 100pts, 2 lines = 400pts, 3 = 900pts, 4 = 1600pts (Tetris!). fall_speed = max(0.1, 1.0 - (level-1) × 0.05)'),

-- 16: Key input handler
((SELECT id FROM flows WHERE app_name = 'tetris'), 'handle_tetris_key()', 'input', 255, 160, 100, 255,
 'ui/tetris.lua:564',
 'INPUT: Keyboard handler called by ElementCanvas on key events',
 'Keys: C=restart, P=pause, A/D=move left/right, S=soft drop, W/Space=hard drop. Only processes key_down=true'),

-- 17: Check game over/paused for input
((SELECT id FROM flows WHERE app_name = 'tetris'), 'Check Game Over/Paused?', 'branch', 255, 140, 140, 255,
 'ui/tetris.lua:586',
 'BRANCH: Block controls if game is over or paused',
 'C and P keys work anytime. Movement keys only work when game is active'),

-- 18: Process key action
((SELECT id FROM flows WHERE app_name = 'tetris'), 'Process Key Action', 'function', 180, 180, 255, 255,
 'ui/tetris.lua:591-604',
 'A/D: Try move horizontal. S: move_down(). W/Space: hard_drop()',
 'Horizontal moves check is_valid_position() before updating x. Soft drop gives no bonus. Hard drop gives +2 pts per row'),

-- 19: Hard drop loop
((SELECT id FROM flows WHERE app_name = 'tetris'), 'hard_drop()', 'loop', 200, 120, 140, 255,
 'ui/tetris.lua:279',
 'LOOP: Calls move_down() until it returns false',
 'while move_down() do score += 2 end. Instantly locks piece at bottom position'),

-- 20: Mouse input handler
((SELECT id FROM flows WHERE app_name = 'tetris'), 'handle_tetris_mouse()', 'input', 255, 180, 200, 255,
 'ui/tetris.lua:545',
 'INPUT: Mouse handler. Left click = rotate piece 90° clockwise',
 'Only processes button=0 (left), button_down=true. Ignores if game over/paused'),

-- 21: Rotate piece
((SELECT id FROM flows WHERE app_name = 'tetris'), 'rotate_piece()', 'function', 180, 140, 220, 255,
 'ui/tetris.lua:119',
 'Matrix rotation: rotated[i][j] = shape[n-j+1][i]',
 '90° clockwise rotation of 4x4 matrix. Checks if rotated piece is valid before applying'),

-- 22: Check rotation valid
((SELECT id FROM flows WHERE app_name = 'tetris'), 'Check Rotation Valid?', 'branch', 255, 160, 220, 255,
 'ui/tetris.lua:558',
 'BRANCH: Can rotated piece exist at current (x,y)?',
 'Uses is_valid_position(). If yes → apply rotation. If no → ignore input (no wall kicks)'),

-- 23: Draw board
((SELECT id FROM flows WHERE app_name = 'tetris'), 'draw_board()', 'render', 140, 180, 255, 255,
 'ui/tetris.lua:324',
 'RENDER: Draws 10x20 grid, placed pieces, ghost piece, current piece',
 '25px blocks. Order: background → grid lines → placed pieces → ghost → current piece'),

-- 24: Get ghost position
((SELECT id FROM flows WHERE app_name = 'tetris'), 'get_ghost_position()', 'loop', 160, 200, 240, 255,
 'ui/tetris.lua:270',
 'LOOP: Finds lowest valid Y by incrementing until collision',
 'while is_valid_position(piece, x, ghost_y + 1) do ghost_y += 1 end. Shows where piece will land'),

-- 25: Draw next piece
((SELECT id FROM flows WHERE app_name = 'tetris'), 'draw_next_piece()', 'render', 160, 220, 180, 255,
 'ui/tetris.lua:390',
 'RENDER: Draws preview of next piece in 4x4 grid',
 'Rendered in sidebar. Shows game.next_piece_type from SHAPES table'),

-- 26: Draw UI elements
((SELECT id FROM flows WHERE app_name = 'tetris'), 'Draw UI Elements', 'render', 180, 200, 220, 255,
 'ui/tetris.lua:443-541',
 'RENDER: Title, score, lines, level, controls, overlays',
 'NanoVG text rendering. Game over overlay: semi-transparent black + red text. Pause overlay: yellow text');

-- Create nodes with positions (using auto-layout)
INSERT INTO nodes (flow_id, node_type_id, label, x, y) VALUES
((SELECT id FROM flows WHERE app_name = 'tetris'), 1, 'START:\ninit_game()', 100, 100),
((SELECT id FROM flows WHERE app_name = 'tetris'), 2, 'init_board()\n20 rows × 10 cols', 100, 220),
((SELECT id FROM flows WHERE app_name = 'tetris'), 3, 'spawn_piece()\nRandom: I,O,T,S,Z,J,L', 100, 340),
((SELECT id FROM flows WHERE app_name = 'tetris'), 4, 'Can Spawn?', 100, 460),
((SELECT id FROM flows WHERE app_name = 'tetris'), 5, 'MAIN LOOP\nrender_tetris()\n~60 FPS', 400, 100),
((SELECT id FROM flows WHERE app_name = 'tetris'), 6, 'Game State?\nover/paused/playing', 400, 220),
((SELECT id FROM flows WHERE app_name = 'tetris'), 7, 'Fall Timer?\ntime >= fall_speed', 600, 220),
((SELECT id FROM flows WHERE app_name = 'tetris'), 8, 'move_down()\ny += 1', 800, 220),
((SELECT id FROM flows WHERE app_name = 'tetris'), 9, 'is_valid_position()\ncollision check', 800, 340),
((SELECT id FROM flows WHERE app_name = 'tetris'), 10, 'Can Move\nDown?', 800, 460),
((SELECT id FROM flows WHERE app_name = 'tetris'), 11, 'lock_piece()\nwrite to board', 600, 580),
((SELECT id FROM flows WHERE app_name = 'tetris'), 12, 'Placed\nAbove Board?', 600, 700),
((SELECT id FROM flows WHERE app_name = 'tetris'), 13, 'clear_lines()\nscan & remove', 600, 820),
((SELECT id FROM flows WHERE app_name = 'tetris'), 14, 'Lines\nCleared?', 600, 940),
((SELECT id FROM flows WHERE app_name = 'tetris'), 15, 'Update Score\nlines² × 100 × level', 400, 940),
((SELECT id FROM flows WHERE app_name = 'tetris'), 16, 'INPUT:\nhandle_tetris_key()\nA,D,S,W,P,C', -200, 340),
((SELECT id FROM flows WHERE app_name = 'tetris'), 17, 'Game Over\nor Paused?', -200, 460),
((SELECT id FROM flows WHERE app_name = 'tetris'), 18, 'Process Action\nmove/drop/rotate', -200, 580),
((SELECT id FROM flows WHERE app_name = 'tetris'), 19, 'hard_drop()\nloop move_down()', -200, 700),
((SELECT id FROM flows WHERE app_name = 'tetris'), 20, 'INPUT:\nhandle_tetris_mouse()\nLeft Click', -500, 340),
((SELECT id FROM flows WHERE app_name = 'tetris'), 21, 'rotate_piece()\nmatrix transform', -500, 460),
((SELECT id FROM flows WHERE app_name = 'tetris'), 22, 'Rotation\nValid?', -500, 580),
((SELECT id FROM flows WHERE app_name = 'tetris'), 23, 'draw_board()\ngrid + pieces', 400, 580),
((SELECT id FROM flows WHERE app_name = 'tetris'), 24, 'get_ghost_position()\nloop find bottom', 200, 700),
((SELECT id FROM flows WHERE app_name = 'tetris'), 25, 'draw_next_piece()\n4×4 preview', 400, 700),
((SELECT id FROM flows WHERE app_name = 'tetris'), 26, 'Draw UI\nscore/level/overlays', 400, 820);

-- Create connections (edges in the flow graph)
-- Main initialization flow
INSERT INTO connections (flow_id, from_node_id, to_node_id, label) VALUES
-- Init sequence
((SELECT id FROM flows WHERE app_name = 'tetris'), 1, 2, NULL),
((SELECT id FROM flows WHERE app_name = 'tetris'), 2, 3, NULL),
((SELECT id FROM flows WHERE app_name = 'tetris'), 3, 4, NULL),
((SELECT id FROM flows WHERE app_name = 'tetris'), 4, 5, 'valid'),

-- Main loop
((SELECT id FROM flows WHERE app_name = 'tetris'), 5, 6, NULL),
((SELECT id FROM flows WHERE app_name = 'tetris'), 6, 7, 'playing'),
((SELECT id FROM flows WHERE app_name = 'tetris'), 7, 8, 'elapsed'),
((SELECT id FROM flows WHERE app_name = 'tetris'), 8, 9, NULL),
((SELECT id FROM flows WHERE app_name = 'tetris'), 9, 10, NULL),

-- Move down - success path
((SELECT id FROM flows WHERE app_name = 'tetris'), 10, 5, 'yes'),

-- Move down - lock path
((SELECT id FROM flows WHERE app_name = 'tetris'), 10, 11, 'no'),
((SELECT id FROM flows WHERE app_name = 'tetris'), 11, 12, NULL),
((SELECT id FROM flows WHERE app_name = 'tetris'), 12, 13, 'no'),
((SELECT id FROM flows WHERE app_name = 'tetris'), 13, 14, NULL),
((SELECT id FROM flows WHERE app_name = 'tetris'), 14, 15, 'yes'),
((SELECT id FROM flows WHERE app_name = 'tetris'), 14, 3, 'no'),
((SELECT id FROM flows WHERE app_name = 'tetris'), 15, 3, NULL),

-- Game over path
((SELECT id FROM flows WHERE app_name = 'tetris'), 12, 4, 'yes'),
((SELECT id FROM flows WHERE app_name = 'tetris'), 4, 4, 'invalid'),

-- Keyboard input flow
((SELECT id FROM flows WHERE app_name = 'tetris'), 16, 17, NULL),
((SELECT id FROM flows WHERE app_name = 'tetris'), 17, 18, 'no'),
((SELECT id FROM flows WHERE app_name = 'tetris'), 18, 9, NULL),
((SELECT id FROM flows WHERE app_name = 'tetris'), 18, 19, 'hard drop'),
((SELECT id FROM flows WHERE app_name = 'tetris'), 19, 8, NULL),

-- Mouse input flow
((SELECT id FROM flows WHERE app_name = 'tetris'), 20, 21, NULL),
((SELECT id FROM flows WHERE app_name = 'tetris'), 21, 22, NULL),
((SELECT id FROM flows WHERE app_name = 'tetris'), 22, 9, 'yes'),

-- Rendering flow
((SELECT id FROM flows WHERE app_name = 'tetris'), 7, 23, 'not elapsed'),
((SELECT id FROM flows WHERE app_name = 'tetris'), 23, 24, NULL),
((SELECT id FROM flows WHERE app_name = 'tetris'), 24, 25, NULL),
((SELECT id FROM flows WHERE app_name = 'tetris'), 25, 26, NULL),
((SELECT id FROM flows WHERE app_name = 'tetris'), 26, 5, NULL);
