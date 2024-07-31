const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const std = @import("std");
const emu = @import("chip8.zig");

var texture: ?*c.SDL_Texture = null;
var rnd = std.Random.DefaultPrng.init(64);

pub fn main() !void {
    var chip8: emu = .{};
    chip8.reset();
    chip8.step();
    chip8.step();
    chip8.step();

    // const op: u16 = 0x31AB;
    // std.debug.print("Op Code: {X}\n", .{op});
    // const x: u4 = (op & 0xF000) >> 12;
    // std.debug.print("x: {X}\n", .{x});
    // const y: u4 = (op & 0x0F00) >> 8;
    // std.debug.print("y: {X}\n", .{y});
    // const a: u4 = (op & 0x00F0) >> 4;
    // std.debug.print("a: {X}\n", .{a});
    // const b: u4 = op & 0x000F;
    // std.debug.print("b: {X}\n", .{b});

    // const xy: u8 = (op & 0xFF00) >> 8;
    // std.debug.print("xy: {X}\n", .{xy});
    // const ab: u8 = (op & 0x00FF);
    // std.debug.print("ab: {X}\n", .{ab});
    // const yab: u12 = (op & 0x0FFF);
    // std.debug.print("yab: {X}\n", .{yab});

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

    var quit = true;
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

        writeTexture();

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

fn writeTexture() void {
    var bytes: ?[*]u32 = null;
    var pitch: c_int = 0;
    _ = c.SDL_LockTexture(texture, null, @ptrCast(&bytes), &pitch);

    var y: usize = 0;
    while (y < 32) : (y += 1) {
        var x: usize = 0;
        while (x < 64) : (x += 1) {
            const random_pixel = rnd.random().boolean();
            bytes.?[y * 64 + x] = if (random_pixel) 0xFFFFFFFF else 0x000000FF;
        }
    }
    c.SDL_UnlockTexture(texture);
}
