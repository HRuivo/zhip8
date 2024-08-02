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

    cpu.v[0] = 0xFF;
    cpu.v[1] = 0xFF;
    cpu.v[2] = 3;
    cpu.i = 0x0200 + 0x0020;

    cpu.memWrite2(0x0200 + 0x0000, 0x8124);
    cpu.memWrite2(0x0200 + 0x0002, 0x0000);
    cpu.memWrite2(0x0200 + 0x0004, 0x00E0);
    cpu.memWrite2(0x0200 + 0x0006, 0xD126);
    cpu.memWrite2(0x0200 + 0x0008, 0xD12E);

    cpu.memWrite2(0x0200 + 0x000a, 0x0000);

    cpu.memWrite2(0x0200 + 0x0020, 0xc3bd);
    cpu.memWrite2(0x0200 + 0x0022, 0x8991);
    cpu.memWrite2(0x0200 + 0x0024, 0xbdc3);

    cpu.memWrite2(0x0200 + 0x0026, 0x3c7e);
    cpu.memWrite2(0x0200 + 0x0028, 0x7e5a);
    cpu.memWrite2(0x0200 + 0x002a, 0x7e3c);
    cpu.memWrite2(0x0200 + 0x002c, 0x016f);
    cpu.memWrite2(0x0200 + 0x002e, 0xf6ba);
    cpu.memWrite2(0x0200 + 0x0030, 0xbca2);
    cpu.memWrite2(0x0200 + 0x0032, 0x2200);

    cpu.step();
    cpu.step();
    cpu.step();
    cpu.step();
    cpu.v[1] = 10;
    cpu.v[2] = 10;
    cpu.i = 0x0200 + 0x0026;
    cpu.step();
    cpu.step();
    cpu.step();

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
                },
                else => {},
            }
        }

        _ = c.SDL_RenderClear(renderer);

        writeTexture(cpu);

        var dest = c.SDL_Rect{
            .x = 0,
            .y = 0,
            .w = 512,
            .h = 256,
        };
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
