const std = @import("std");

const RAM_SIZE: usize = 4096;
const NUM_REGS: u8 = 16;
const STACK_SIZE: u8 = 16;
const NUM_KEYS: u8 = 16;
const FONTSET_SIZE: u8 = 80;

const START_ADDR: u16 = 0x200;

const SCREEN_WIDTH: usize = 64;
const SCREEN_HEIGHT: usize = 32;

const Operation = union(enum) {
    Nop,
    Return,
    Clear,
    Jump: u16,
    Call: u16,
    SkipVxEqualNN: struct { index: u4, nn: u8 },
    SkipVxNotEqualNN: struct { index: u4, nn: u8 },
    SkipVxEqualVy: struct { dest: u4, source: u4 },
    SkipVxNotEqualVy: struct { dest: u4, source: u4 },
    VxNN: struct { index: u4, nn: u8 },
    Add: struct { index: u4, nn: u8 },
    VxVy: struct { dest: u4, source: u4 },
    VxOrVy: struct { dest: u4, source: u4 },
    VxAndVy: struct { dest: u4, source: u4 },
    VxXorVy: struct { dest: u4, source: u4 },
    VxAddVy: struct { dest: u4, source: u4 },
    VxSubVy: struct { dest: u4, source: u4 },
    VxRightShift: u4,
    VxLeftShift: u4,
    VySubVx: struct { dest: u4, source: u4 },
    SetI: u16,
    JumpV0PlusNNN: u16,
    VxRandAndNN: struct { index: u4, nn: u8 },
    Draw: struct { x: u4, y: u4, height: u4 },
    SkipKeyPress: u4,
    SkipKeyRelease: u4,
    VxDt: u4,
    WaitKey: u4,
    DtVx: u4,
    StVx: u4,
    IPlusVx: u4,
    IFont: u4,
    BCD: u4,
    StoreV0MinusVx: u4,
    LoadV0MinusVx: u4,
};

const BitMask = enum(u16) {
    MaskF000 = 0xF000,
    Mask0F00 = 0x0F00,
    Mask00F0 = 0x00F0,
    Mask000F = 0x000F,
    Mask00FF = 0x00FF,
    Mask0FFF = 0x0FFF,

    fn maskBits(op: u16, mask: BitMask) u16 {
        return op & @intFromEnum(mask);
    }
};

const fontset = [_]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

pub const Emu = struct {
    pc: u16 = START_ADDR,

    stack: [STACK_SIZE]u16 = undefined,
    sp: u16 = 0,

    v: [NUM_REGS]u8 = undefined,
    i: u16 = 0,

    dt: u8 = 0,
    st: u8 = 0,

    /// Memory Map
    ///
    /// 0x000-0x1FF - Interpreter
    /// 0x050-0x0A0 = Used for 4x5 pixel font set
    /// 0x200-0xFFF = Program ROM & Working RAM
    mem: [RAM_SIZE]u8 = undefined,

    screen: [SCREEN_WIDTH * SCREEN_HEIGHT]u8 = undefined,
    keys: [NUM_KEYS]bool = undefined,

    pub fn reset(self: *@This()) void {
        self.pc = START_ADDR;
        self.i = 0; // 0x0200 + 0x0026;
        self.sp = 0;
        self.dt = 0;
        self.st = 0;

        for (&self.v) |*register| {
            register.* = 0x00;
        }

        for (&self.mem) |*register| {
            register.* = 0x00;
        }

        for (&self.stack) |*register| {
            register.* = 0x00;
        }

        for (&self.keys) |*state| {
            state.* = false;
        }

        for (fontset, 80..) |c, idx| {
            self.mem[idx] = c;
        }

        self.clearScreen();
    }

    pub fn loadRom(self: *@This(), filename: []const u8) void {
        var input_file = std.fs.cwd().openFile(filename, .{}) catch {
            std.debug.print("failed to open rom file '{s}'.", .{filename});
            return;
        };
        defer input_file.close();

        std.debug.print("Loading ROM\n", .{});
        const size = input_file.getEndPos() catch {
            std.debug.print("failed to read rom end position.", .{});
            return;
        };

        std.debug.print("ROM File Size {}\n", .{size});
        var reader = input_file.reader();

        var i: u32 = 0;
        while (i < size) : (i += 1) {
            self.mem[i + START_ADDR] = reader.readByte() catch {
                std.debug.print("failed to read byte from rom file", .{});
                return;
            };
        }

        std.debug.print("ROM Loaded.\n", .{});
    }

    pub fn step(self: *@This()) void {
        const op = self.fetch();
        self.execute(op);
    }

    pub fn tickTimers(self: *@This()) void {
        if (self.dt > 0) {
            self.dt -= 1;
        }

        if (self.st > 0) {
            if (self.st == 1) {
                // BEEP
            }
            self.st -= 1;
        }
    }

    fn fetch(self: *@This()) Operation {
        const opcode: u16 = self.memRead2(self.pc);
        const operation = decode(opcode);
        self.pc += 2;
        return operation;
    }

    fn decode(op: u16) Operation {
        const x: u4 = @truncate((op & 0xF000) >> 12);
        const y: u4 = @truncate((op & 0x0F00) >> 8);
        const a: u4 = @truncate((op & 0x00F0) >> 4);
        const b: u4 = @truncate((op & 0x000F));
        const nn: u8 = @truncate((op & 0x00FF));

        switch (x) {
            0x0 => {
                const yab = (op & 0x0FFF);
                switch (yab) {
                    // Nop
                    0x000 => return Operation.Nop,
                    // Clear Screen
                    0x0E0 => return Operation.Clear,
                    // Return
                    0x0EE => return Operation.Return,
                    else => unreachable,
                }
            },
            // Jump NNN
            0x1 => {
                return Operation{ .Jump = BitMask.maskBits(op, .Mask0FFF) };
            },
            // CALL NNN
            0x2 => {
                return Operation{ .Call = BitMask.maskBits(op, .Mask0FFF) };
            },
            // SKIP VX == NN
            0x3 => {
                return Operation{
                    .SkipVxEqualNN = .{
                        .index = y,
                        .nn = nn,
                    },
                };
            },
            // SKIP VX != NN
            0x4 => {
                return Operation{
                    .SkipVxNotEqualNN = .{
                        .index = y,
                        .nn = nn,
                    },
                };
            },
            // SKIP VX == VY
            0x5 => {
                return Operation{
                    .SkipVxEqualVy = .{
                        .dest = y,
                        .source = a,
                    },
                };
            },
            // VX = NN
            0x6 => {
                return Operation{
                    .VxNN = .{
                        .index = y,
                        .nn = nn,
                    },
                };
            },
            // VX += NN
            0x7 => {
                return Operation{
                    .Add = .{
                        .index = y,
                        .nn = nn,
                    },
                };
            },
            0x8 => {
                switch (b) {
                    // VX = VY
                    0x0 => {
                        return Operation{
                            .VxVy = .{ .dest = y, .source = a },
                        };
                    },
                    // VX |= VY
                    0x1 => {
                        return Operation{
                            .VxOrVy = .{ .dest = y, .source = a },
                        };
                    },
                    // VX &= VY
                    0x2 => {
                        return Operation{
                            .VxAndVy = .{ .dest = y, .source = a },
                        };
                    },
                    // VX ^= VY
                    0x3 => {
                        return Operation{
                            .VxXorVy = .{ .dest = y, .source = a },
                        };
                    },
                    // VX += VY
                    0x4 => {
                        return Operation{
                            .VxAddVy = .{ .dest = y, .source = a },
                        };
                    },
                    // VX -= VY
                    0x5 => {
                        return Operation{
                            .VxSubVy = .{ .dest = y, .source = a },
                        };
                    },
                    // VX >>= 1
                    0x6 => {
                        return Operation{
                            .VxRightShift = y,
                        };
                    },
                    // VX = VY - VX
                    0x7 => {
                        return Operation{
                            .VySubVx = .{ .dest = y, .source = a },
                        };
                    },
                    // VX <<= 1
                    0xE => {
                        return Operation{
                            .VxLeftShift = y,
                        };
                    },
                    else => unreachable,
                }
            },
            0x9 => {
                return Operation{
                    .SkipVxNotEqualVy = .{ .dest = y, .source = a },
                };
            },
            0xA => {
                return Operation{
                    .SetI = BitMask.maskBits(op, .Mask0FFF),
                };
            },
            0xB => {
                return Operation{
                    .JumpV0PlusNNN = BitMask.maskBits(op, .Mask0FFF),
                };
            },
            0xC => {
                return Operation{ .VxRandAndNN = .{
                    .index = y,
                    .nn = nn,
                } };
            },
            // DRAW
            0xD => {
                return Operation{
                    .Draw = .{
                        .x = y,
                        .y = a,
                        .height = b,
                    },
                };
            },
            0xE => {
                switch (nn) {
                    0x9E => return Operation{ .SkipKeyPress = y },
                    0xA1 => return Operation{ .SkipKeyRelease = y },
                    else => unreachable,
                }
            },
            0xF => {
                switch (nn) {
                    0x07 => return Operation{ .VxDt = y },
                    0x0A => return Operation{ .WaitKey = y },
                    0x15 => return Operation{ .DtVx = y },
                    0x18 => return Operation{ .StVx = y },
                    0x1E => return Operation{ .IPlusVx = y },
                    0x29 => return Operation{ .IFont = y },
                    0x33 => return Operation{ .BCD = y },
                    0x55 => return Operation{ .StoreV0MinusVx = y },
                    0x65 => return Operation{ .LoadV0MinusVx = y },
                    else => unreachable,
                }
            },
        }
    }

    fn execute(self: *@This(), op: Operation) void {
        //std.debug.print("PC: {X}\n", .{self.pc});

        switch (op) {
            Operation.Nop => {},
            Operation.Return => {
                const ret_addr = self.pop();
                self.pc = ret_addr;
            },
            Operation.Clear => {
                self.clearScreen();
            },
            Operation.Jump => |nnn| {
                self.pc = nnn;
            },
            Operation.Call => |nnn| {
                self.push(self.pc);
                self.pc = nnn;
            },
            Operation.SkipVxEqualNN => |data| {
                if (self.v[data.index] == data.nn) {
                    self.pc += 2;
                }
            },
            Operation.SkipVxNotEqualNN => |data| {
                if (self.v[data.index] != data.nn) {
                    self.pc += 2;
                }
            },
            Operation.SkipVxEqualVy => |data| {
                if (self.v[data.dest] == self.v[data.source]) {
                    self.pc += 2;
                }
            },
            Operation.SkipVxNotEqualVy => |data| {
                if (self.v[data.dest] != self.v[data.source]) {
                    self.pc += 2;
                }
            },
            Operation.VxNN => |data| {
                self.v[data.index] = data.nn;
            },
            Operation.Add => |data| {
                const a = self.v[data.index];
                self.v[data.index] = @addWithOverflow(a, data.nn)[0];
            },
            Operation.VxVy => |data| {
                self.v[data.dest] = self.v[data.source];
            },
            Operation.VxOrVy => |data| {
                self.v[data.dest] |= self.v[data.source];
            },
            Operation.VxAndVy => |data| {
                self.v[data.dest] &= self.v[data.source];
            },
            Operation.VxXorVy => |data| {
                self.v[data.dest] ^= self.v[data.source];
            },
            Operation.VxAddVy => |data| {
                const sum_result = @addWithOverflow(
                    self.v[data.dest],
                    self.v[data.source],
                );
                self.v[data.dest] = sum_result[0];
                self.v[0xF] = sum_result[1];
            },
            Operation.VxSubVy => |data| {
                const sub_result = @subWithOverflow(
                    self.v[data.dest],
                    self.v[data.source],
                );
                self.v[data.dest] = sub_result[0];
                self.v[0xF] = sub_result[1];
            },
            Operation.VxRightShift => |index| {
                const lsb = self.v[index] & 1;
                self.v[index] >>= 1;
                self.v[0xF] = lsb;
            },
            Operation.VxLeftShift => |index| {
                const msb = (self.v[index] >> 7) & 1;
                self.v[index] <<= 1;
                self.v[0xF] = msb;
            },
            Operation.SetI => |nnn| {
                self.i = nnn;
            },
            Operation.JumpV0PlusNNN => |nnn| {
                self.pc = (self.v[0]) + nnn;
            },
            Operation.VxRandAndNN => |data| {
                const rng = 0;
                self.v[data.index] = rng & data.nn;
            },
            Operation.SkipKeyPress => |index| {
                const vx = self.v[index];
                const key = self.keys[vx];
                if (key) {
                    self.pc += 2;
                }
            },
            Operation.SkipKeyRelease => |index| {
                const vx = self.v[index];
                const key = self.keys[vx];
                if (!key) {
                    self.pc += 2;
                }
            },
            Operation.WaitKey => |index| {
                var pressed: bool = false;
                for (self.keys, 0..) |state, i| {
                    if (state) {
                        self.v[index] = @intCast(i);
                        pressed = true;
                        break;
                    }
                }
            },
            Operation.VxDt => |index| {
                self.v[index] = self.dt;
            },
            Operation.DtVx => |index| {
                self.dt = self.v[index];
            },
            Operation.StVx => |index| {
                self.st = self.v[index];
            },
            Operation.IPlusVx => |index| {
                const vx = self.v[index];
                self.i = @addWithOverflow(self.i, vx)[0];
            },
            Operation.IFont => |index| {
                const c = self.v[index];
                self.i = c * 5;
            },
            Operation.Draw => |data| {
                const x_coord = self.v[data.x];
                const y_coord = self.v[data.y];
                const num_rows = data.height;

                var y: u8 = 0;
                while (y < num_rows) : (y += 1) {
                    const spr: u8 = self.mem[self.i + y];

                    var x: u8 = 0;
                    while (x < 8) : (x += 1) {
                        const v: u8 = 0x80;
                        if ((spr & (v >> @truncate(x))) != 0) {
                            const tX = (x_coord + x) % SCREEN_WIDTH;
                            const tY = (y_coord + y) % SCREEN_HEIGHT;

                            const idx = tX + tY * SCREEN_WIDTH;

                            self.screen[idx] ^= 1;
                            if (self.screen[idx] == 0) {
                                self.v[0x0F] = 1;
                            }
                        }
                    }
                }
            },
            Operation.BCD => |index| {
                //const vx: f16 = @floatFromInt(self.v[index]);
                const vx = self.v[index];

                const hundreds: u8 = std.math.divFloor(u8, vx, 100.0) catch 0;
                const tens: u8 = std.math.mod(u8, std.math.divFloor(u8, vx, 10.0) catch 0, 10.0) catch 0;
                const ones: u8 = std.math.mod(u8, vx, 10.0) catch 0;

                self.mem[self.i] = hundreds;
                self.mem[self.i + 1] = tens;
                self.mem[self.i + 2] = ones;
            },
            Operation.StoreV0MinusVx => |index| {
                const x = index;
                const i = self.i;
                for (0..(x + 1)) |idx| {
                    self.mem[i + idx] = self.v[idx];
                }
            },
            Operation.LoadV0MinusVx => |index| {
                const x = index;
                const i = self.i;
                for (0..(x + 1)) |idx| {
                    self.v[idx] = self.mem[i + idx];
                }
            },
            else => unreachable,
        }
    }

    pub fn memWrite(self: *@This(), address: u16, value: u8) void {
        self.mem[address] = value;
    }

    pub fn memWrite2(self: *@This(), address: u16, value: u16) void {
        const xy: u8 = @truncate((value & 0xFF00) >> 8);
        const ab: u8 = @truncate((value & 0x00FF));
        self.memWrite(address, xy);
        self.memWrite(address + 0x0001, ab);
    }

    pub fn memRead(self: @This(), address: u16) u8 {
        return self.mem[address];
    }

    pub fn memRead2(self: @This(), address: u16) u16 {
        const opcode: u16 = @as(u16, (self.memRead(address))) << 8 | self.memRead(address + 1);
        return opcode;
    }

    fn clearScreen(self: *@This()) void {
        for (&self.screen) |*pixel| {
            pixel.* = 0x00;
        }
    }

    fn push(self: *@This(), value: u16) void {
        self.stack[self.sp] = value;
        self.sp += 1;
    }

    fn pop(self: *@This()) u16 {
        if (self.sp == 0x0) return 0x0; // unreachable
        self.sp -= 1;
        return self.stack[self.sp];
    }

    pub fn keyPress(self: *@This(), key_index: u8, pressed: bool) void {
        if (key_index < self.keys.len) {
            self.keys[key_index] = pressed;
        }
    }
};

test "nop" {
    var chip: Emu = .{};
    chip.reset();
    chip.memWrite2(START_ADDR + 0x0000, 0x0000);

    chip.step();

    try std.testing.expect(chip.pc == START_ADDR + 0x0002);
}

test "clear_screen" {
    var chip: Emu = .{};
    chip.reset();

    chip.memWrite2(START_ADDR + 0x0000, 0xD001);
    chip.memWrite2(START_ADDR + 0x0000, 0x00E0);

    const gfx_start_addr = START_ADDR + 0x010;
    chip.memWrite2(gfx_start_addr, 0x9090);
    chip.i = START_ADDR + gfx_start_addr;

    chip.step();
    chip.step();

    try std.testing.expect(chip.screen[0] == 0x0);
}

test "call" {
    var chip: Emu = .{};
    chip.reset();

    chip.memWrite2(START_ADDR, 0x2345);

    chip.step();

    try std.testing.expect(chip.pc == 0x0345);
}
