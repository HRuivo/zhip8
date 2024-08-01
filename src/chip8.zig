const std = @import("std");

const RAM_SIZE: usize = 4096;
const NUM_REGS: u8 = 16;
const STACK_SIZE: u8 = 16;

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

pc: u16 = START_ADDR,

stack: [STACK_SIZE]u16,
sp: u16 = 0,

v: [NUM_REGS]u8,
i: u16 = 0,

dt: u8 = 0,
st: u8 = 0,

mem: [RAM_SIZE]u8,
screen: [SCREEN_WIDTH * SCREEN_HEIGHT]u8,

pub fn reset(self: *@This()) void {
    self.pc = START_ADDR;
    self.i = 0x0200 + 0x0026;
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
    self.clearScreen();
}

pub fn step(self: *@This()) void {
    const op = self.fetch();
    self.execute(op);
}

fn tickTimers(self: *@This()) void {
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
        else => {
            std.debug.print("unimplemented op code\n", .{});
            return Operation.Nop;
        },
    }
}

fn execute(self: *@This(), op: Operation) void {
    defer std.debug.print("\n", .{});

    std.debug.print("PC: {X}\n", .{self.pc});

    switch (op) {
        Operation.Nop => {},
        Operation.Return => {
            const ret_addr = self.pop();
            self.pc = ret_addr;
            std.debug.print("Returning to: {X}", .{ret_addr});
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
        else => {},
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
