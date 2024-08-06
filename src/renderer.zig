const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

pub const RendererError = error{
    FailedInitialization,
};

pub const Renderer = struct {
    render_texture: ?*c.SDL_Texture = null,
    screen: ?*c.SDL_Window = null,
    renderer: ?*c.SDL_Renderer = null,

    pub fn init(title: [*c]const u8, w: c_int, h: c_int, scale: c_int) RendererError!@This() {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
            return RendererError.FailedInitialization;
        }

        const viewport_scale = if (scale == 0) 8 else scale;
        var renderer: Renderer = .{};
        renderer.screen = c.SDL_CreateWindow(
            title,
            c.SDL_WINDOWPOS_UNDEFINED,
            c.SDL_WINDOWPOS_UNDEFINED,
            w * viewport_scale,
            h * viewport_scale,
            c.SDL_WINDOW_OPENGL,
        ) orelse {
            c.SDL_Log("Unable to create widnow: %s", c.SDL_GetError());
            return RendererError.FailedInitialization;
        };

        renderer.renderer = c.SDL_CreateRenderer(
            renderer.screen,
            -1,
            0,
        ) orelse {
            c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
            return RendererError.FailedInitialization;
        };

        renderer.render_texture = c.SDL_CreateTexture(
            renderer.renderer,
            c.SDL_PIXELFORMAT_RGBA8888,
            c.SDL_TEXTUREACCESS_STREAMING,
            w,
            h,
        ) orelse {
            c.SDL_Log("Failed to create a texture: %s", c.SDL_GetError());
            return RendererError.FailedInitialization;
        };

        return renderer;
    }

    pub fn deinit(self: *@This()) void {
        c.SDL_Quit();

        if (self.screen) |s| {
            c.SDL_DestroyWindow(s);
        }

        if (self.renderer) |r| {
            c.SDL_DestroyRenderer(r);
        }

        if (self.render_texture) |t| {
            c.SDL_DestroyTexture(t);
        }

        c.SDL_Log("SDL Cleared.", "");
    }

    pub fn present(self: @This(), pixel_data: []u8) void {
        _ = c.SDL_RenderClear(self.renderer);

        self.writeTexture(pixel_data);

        var dest = c.SDL_Rect{ .x = 0, .y = 0, .w = 512, .h = 256 };
        _ = c.SDL_RenderCopy(self.renderer, self.render_texture, null, &dest);
        _ = c.SDL_RenderPresent(self.renderer);

        c.SDL_Delay(17);
    }

    fn writeTexture(self: @This(), pixels: []u8) void {
        var bytes: ?[*]u32 = null;
        var pitch: c_int = 0;
        _ = c.SDL_LockTexture(self.render_texture, null, @ptrCast(&bytes), &pitch);

        var y: usize = 0;
        while (y < 32) : (y += 1) {
            var x: usize = 0;
            while (x < 64) : (x += 1) {
                bytes.?[y * 64 + x] = if (pixels[y * 64 + x] == 1) 0xFFFFFFFF else 0x000000FF;
            }
        }
        c.SDL_UnlockTexture(self.render_texture);
    }
};
