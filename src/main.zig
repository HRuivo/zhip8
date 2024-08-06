const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const Emu = @import("chip8.zig").Emu;
const Renderer = @import("renderer.zig").Renderer;

var texture: ?*c.SDL_Texture = null;
var rnd = std.Random.DefaultPrng.init(64);

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var chip8 = try allocator.create(Emu);
    chip8.reset();

    var arg_it = try std.process.argsWithAllocator(allocator);
    _ = arg_it.skip();

    const filename: []const u8 = arg_it.next() orelse {
        std.debug.print("No ROM file given.\n", .{});
        return;
    };

    std.debug.print("filename={s}\n", .{filename});
    chip8.loadRom(filename);

    var renderer: Renderer = Renderer.init(
        "Zhip8 _ Chip-8 Emulation",
        64,
        32,
        0,
    ) catch {
        std.debug.print("Failed to initialize renderer.\n", .{});
        return;
    };
    c.SDL_Delay(2000);
    defer renderer.deinit();

    var quit = false;
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    quit = true;
                },
                c.SDL_KEYDOWN => {
                    if (event.key.keysym.scancode == c.SDL_SCANCODE_ESCAPE) {
                        quit = true;
                    }
                },
                else => {},
            }
        }

        for (0..10) |_| {
            chip8.step();
        }
        chip8.tickTimers();

        renderer.present(&chip8.screen);
    }

    // var quit = false;
    // while (!quit) {
    //     var event: c.SDL_Event = undefined;
    //     while (c.SDL_PollEvent(&event) != 0) {
    //         switch (event.type) {
    //             c.SDL_QUIT => {
    //                 quit = true;
    //             },
    //             c.SDL_KEYDOWN => {
    //                 if (event.key.keysym.scancode == c.SDL_SCANCODE_ESCAPE) {
    //                     quit = true;
    //                 }

    //                 const key_code: u8 = keyToButton(event.key.keysym.scancode);
    //                 chip8.keyPress(key_code, true);
    //             },
    //             c.SDL_KEYUP => {
    //                 const key_code: u8 = keyToButton(event.key.keysym.scancode);
    //                 chip8.keyPress(key_code, false);
    //             },
    //             else => {},
    //         }
    //     }
}

fn keyToButton(key: c_uint) u8 {
    return switch (key) {
        c.SDL_SCANCODE_1 => 0x1,
        c.SDL_SCANCODE_2 => 0x2,
        c.SDL_SCANCODE_3 => 0x3,
        c.SDL_SCANCODE_4 => 0xC,

        c.SDL_SCANCODE_Q => 0x4,
        c.SDL_SCANCODE_W => 0x5,
        c.SDL_SCANCODE_E => 0x6,
        c.SDL_SCANCODE_R => 0xD,

        c.SDL_SCANCODE_A => 0x7,
        c.SDL_SCANCODE_S => 0x8,
        c.SDL_SCANCODE_D => 0x9,
        c.SDL_SCANCODE_F => 0xE,

        c.SDL_SCANCODE_Z => 0xA,
        c.SDL_SCANCODE_X => 0x0,
        c.SDL_SCANCODE_C => 0xB,
        c.SDL_SCANCODE_V => 0xF,
        else => 0x0,
    };
}
