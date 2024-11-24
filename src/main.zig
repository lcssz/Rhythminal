const std = @import("std");
const vaxis = @import("vaxis");
pub const panic = vaxis.panic_handler;

const Note = struct {
    column: usize,
    row: usize,
    hit: bool = false,
};

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    tick,
};

const GameState = struct {
    notes: std.ArrayList(Note),
    score: u32 = 0,
    misses: u32 = 0,
    speed: u32 = 1,
    tick_counter: u32 = 0,
    update_frequency: u32 = 3,
};

const Rhythminal = struct {
    allocator: std.mem.Allocator,
    tty: vaxis.Tty,
    vx: vaxis.Vaxis,
    should_quit: bool,
    game_state: GameState,
    table: vaxis.widgets.Table.TableContext,

    pub fn init(allocator: std.mem.Allocator) !Rhythminal {
        return .{
            .allocator = allocator,
            .tty = try vaxis.Tty.init(),
            .vx = try vaxis.init(allocator, .{}),
            .should_quit = false,
            .game_state = .{
                .notes = std.ArrayList(Note).init(allocator),
            },
            .table = .{
                .active_bg = .{ .rgb = .{ 64, 128, 255 } },
                .active_fg = .{ .rgb = .{ 255, 255, 255 } },
                .row_bg_1 = .{ .rgb = .{ 32, 32, 32 } },
                .selected_bg = .{ .rgb = .{ 32, 64, 255 } },
                .header_names = .{ .custom = &.{ "D", "F", "J", "K" } },
                .col_width = .{ .static_all = 3 },
                .header_borders = true,
                .col_borders = true,
            },
        };
    }

    pub fn deinit(self: *Rhythminal) void {
        self.game_state.notes.deinit();
        self.vx.deinit(self.allocator, self.tty.anyWriter());
        self.tty.deinit();
    }

    pub fn run(self: *Rhythminal) !void {
        var loop: vaxis.Loop(Event) = .{
            .tty = &self.tty,
            .vaxis = &self.vx,
        };
        try loop.init();
        try loop.start();
        try self.vx.enterAltScreen(self.tty.anyWriter());
        try self.vx.queryTerminal(self.tty.anyWriter(), 250 * std.time.ns_per_ms);

        // Game loop
        var timer = try std.time.Timer.start();
        const frame_time = 50 * std.time.ns_per_ms;

        while (!self.should_quit) {
            // Process events
            while (loop.tryEvent()) |event| {
                try self.update(event);
            }

            // Check if it's time for the next frame
            if (timer.read() >= frame_time) {
                timer.reset();
                loop.postEvent(.tick);
            }

            try self.draw();
            std.time.sleep(16 * std.time.ns_per_ms);
        }
    }

    fn spawnNote(self: *Rhythminal) !void {
        const column = std.crypto.random.intRangeAtMost(usize, 0, 3);
        try self.game_state.notes.append(.{
            .column = column,
            .row = 0,
        });
    }

    pub fn update(self: *Rhythminal, event: Event) !void {
        switch (event) {
            .key_press => |key| {
                if (key.matches('q', .{})) self.should_quit = true;

                // Check for note hits
                const hit_keys = [_]u8{ 'a', 's', 'j', 'k' };
                for (hit_keys, 0..) |hit_key, column| {
                    if (key.matches(hit_key, .{})) {
                        // Check for notes at the bottom of the screen
                        for (self.game_state.notes.items) |*note| {
                            if (note.column == column and note.row >= 14 and !note.hit) {
                                note.hit = true;
                                self.game_state.score += 100;
                                break;
                            }
                        }
                    }
                }
            },
            .winsize => |ws| try self.vx.resize(self.allocator, self.tty.anyWriter(), ws),
            .tick => {
                // Increment the counter
                self.game_state.tick_counter += 1;

                // Only update note positions when the desired frequency is reached
                if (self.game_state.tick_counter >= self.game_state.update_frequency) {
                    self.game_state.tick_counter = 0; // Reset counter

                    // Move notes down
                    for (self.game_state.notes.items) |*note| {
                        note.row += self.game_state.speed;
                    }

                    // Remove notes that are off screen or hit
                    var i: usize = 0;
                    while (i < self.game_state.notes.items.len) {
                        const note = self.game_state.notes.items[i];
                        if (note.row > 15 or note.hit) {
                            if (note.row > 15 and !note.hit) {
                                self.game_state.misses += 1;
                            }
                            _ = self.game_state.notes.orderedRemove(i);
                        } else {
                            i += 1;
                        }
                    }

                    // Randomly spawn new notes
                    if (std.crypto.random.boolean()) {
                        try self.spawnNote();
                    }
                }
            },
        }
    }

    pub fn draw(self: *Rhythminal) !void {
        const win = self.vx.window();
        win.clear();

        // Draw score
        var score_buf: [32]u8 = undefined;
        const score_text = try std.fmt.bufPrint(&score_buf, "Score: {d} Misses: {d}", .{ self.game_state.score, self.game_state.misses });
        const score_seg = vaxis.Cell.Segment{ .text = score_text };
        _ = try win.print(&.{score_seg}, .{});

        // Draw game area
        const game_win = win.child(.{
            .x_off = 0,
            .y_off = 2,
        });

        // Create visual representation of notes
        var rows = std.ArrayList([]const u8).init(self.allocator);
        defer {
            // Free memory for each row before freeing the ArrayList
            for (rows.items) |row| {
                self.allocator.free(row);
            }
            rows.deinit();
        }

        // Initialize empty rows
        const empty_row = "   |   |   |   ";
        const hit_line = "_o_|_o_|_o_|_o_"; // Hit line pattern
        const hit_row_index = 15; // Position where notes should be hit

        for (0..16) |i| {
            var row: []u8 = undefined;
            if (i == hit_row_index) {
                // If it's the hit line, use the pattern with circles
                row = try self.allocator.dupe(u8, hit_line);
            } else {
                row = try self.allocator.dupe(u8, empty_row);
            }
            try rows.append(row);
        }

        // Place notes in the grid
        for (self.game_state.notes.items) |note| {
            if (note.row < rows.items.len and note.row != hit_row_index) { // Don't overwrite the hit line
                const note_pos = note.column * 4 + 1;
                if (note_pos + 1 <= rows.items[note.row].len) {
                    // First free the old row
                    const old_row = rows.items[note.row];
                    // Create a new row
                    var new_row = try self.allocator.dupe(u8, empty_row);
                    new_row[note_pos] = if (note.hit) 'O' else '#';
                    // Replace the row in the ArrayList
                    rows.items[note.row] = new_row;
                    // Free the old row
                    self.allocator.free(old_row);
                }
            }
        }

        // Draw the grid
        for (rows.items, 0..) |row, i| {
            const row_seg = vaxis.Cell.Segment{
                .text = row,
                .style = if (i == hit_row_index)
                    .{ .bold = true, .fg = .{ .rgb = .{ 255, 255, 0 } } } // Yellow highlight for hit line
                else
                    .{},
            };
            const row_win = game_win.child(.{
                .x_off = 0,
                .y_off = @intCast(i),
            });
            _ = try row_win.print(&.{row_seg}, .{});
        }

        // Draw key guide at the bottom
        const key_guide = " A | S | J | K ";
        const key_win = game_win.child(.{
            .x_off = 0,
            .y_off = @intCast(rows.items.len),
        });
        const key_seg = vaxis.Cell.Segment{ .text = key_guide };
        _ = try key_win.print(&.{key_seg}, .{});

        try self.vx.render(self.tty.anyWriter());
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("memory leak", .{});
        }
    }
    const allocator = gpa.allocator();
    var app = try Rhythminal.init(allocator);
    defer app.deinit();
    try app.run();
}
