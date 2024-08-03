const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const Emu = @import("chip8.zig");

var texture: ?*c.SDL_Texture = null;
var rnd = std.Random.DefaultPrng.init(64);

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var cpu = try allocator.create(Emu);
    cpu.reset();

    var arg_it = try std.process.argsWithAllocator(allocator);
    _ = arg_it.skip();

    const filename: []const u8 = arg_it.next() orelse {
        std.debug.print("No ROM file given.\n", .{});
        return;
    };

    std.debug.print("filename={s}\n", .{filename});
    cpu.loadRom(filename);

    std.debug.print("Starting SDL2...\n", .{});
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    const screen = c.SDL_CreateWindow("Zhip8 Emu", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, 512, 256, c.SDL_WINDOW_OPENGL) orelse {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(screen);

    const renderer = c.SDL_CreateRenderer(screen, -1, 0) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    texture = c.SDL_CreateTexture(renderer, c.SDL_PIXELFORMAT_RGBA8888, c.SDL_TEXTUREACCESS_STREAMING, 64, 32) orelse {
        c.SDL_Log("Failed to create a texture: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyTexture(texture);

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

                    const key_code: u8 = keyToButton(event.key.keysym.scancode);
                    cpu.keyPress(key_code, true);
                },
                c.SDL_KEYUP => {
                    const key_code: u8 = keyToButton(event.key.keysym.scancode);
                    cpu.keyPress(key_code, false);
                },
                else => {},
            }
        }

        _ = c.SDL_RenderClear(renderer);

        for (0..10) |_| {
            cpu.step();
        }
        cpu.tickTimers();

        writeTexture(cpu);

        var dest = c.SDL_Rect{ .x = 0, .y = 0, .w = 512, .h = 256 };
        _ = c.SDL_RenderCopy(renderer, texture, null, &dest);
        _ = c.SDL_RenderPresent(renderer);

        c.SDL_Delay(17);
    }
}

fn writeTexture(emu: *Emu) void {
    var bytes: ?[*]u32 = null;
    var pitch: c_int = 0;
    _ = c.SDL_LockTexture(texture, null, @ptrCast(&bytes), &pitch);

    var y: usize = 0;
    while (y < 32) : (y += 1) {
        var x: usize = 0;
        while (x < 64) : (x += 1) {
            //const random_pixel = rnd.random().boolean();
            //bytes.?[y * 64 + x] = if (random_pixel) 0xFFFFFFFF else 0x000000FF;
            bytes.?[y * 64 + x] = if (emu.screen[y * 64 + x] == 1) 0xFFFFFFFF else 0x000000FF;
        }
    }
    c.SDL_UnlockTexture(texture);
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
