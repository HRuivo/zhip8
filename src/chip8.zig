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
};

pc: u16 = START_ADDR,

v: [NUM_REGS]u8 = undefined,
i: u16 = 0,

dt: u8 = 0,
st: u8 = 0,

stack: [STACK_SIZE]u16 = undefined,
sp: u16 = 0,

mem: [RAM_SIZE]u8 = undefined,

screen: [SCREEN_WIDTH * SCREEN_HEIGHT]bool = undefined,

pub fn reset(self: *@This()) void {
    self.pc = START_ADDR;
    self.i = 0;
    self.sp = 0;
    self.dt = 0;
    self.st = 0;
    for (0..self.v.len) |i| {
        self.v[i] = 0x0;
    }
    for (0..self.mem.len) |i| {
        self.mem[i] = 0x0;
    }
    for (0..self.stack.len) |i| {
        self.stack[i] = 0x0;
    }
}

pub fn step(self: *@This()) void {
    const op = self.fetch();
    self.execute(op);
}

fn tick_timers(self: *@This()) void {
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
    const operation = decode(0x00E0);
    self.pc += 2;
    return operation;
}

fn decode(op: u16) Operation {
    const x = (op & 0xF000) >> 12;
    std.debug.print("op x: {X}\n", .{x});

    switch (x) {
        0x0 => {
            const yab = (op & 0x0FFF);
            switch (yab) {
                0x000 => return Operation.Nop,
                0x0E0 => return Operation.Clear,
                0x0EE => return Operation.Return,
                else => unreachable,
            }
        },
        else => {
            std.debug.print("unimplemented op code\n", .{});
            return Operation.Nop;
        },
    }
}

fn execute(self: *@This(), op: Operation) void {
    defer std.debug.print("\n", .{});

    switch (op) {
        Operation.Nop => {
            std.debug.print("Skipping...", .{});
        },
        Operation.Return => {
            std.debug.print("Returning", .{});
        },
        Operation.Clear => {
            std.debug.print("Clearing Screen", .{});
        },
        Operation.Jump => |code| {
            _ = code;
        },
        //else => {},
    }
    _ = self;
}
