const std = @import("std");

/// Un color simple en RGB (0-255 cada canal).
pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};

/// El framebuffer: un lienzo en memoria donde vamos a "pintar" píxeles
/// antes de guardarlos en disco. width * height * 3 bytes (RGB).
pub const Framebuffer = struct {
    width: usize,
    height: usize,
    pixels: []u8, // RGB, fila por fila, de arriba hacia abajo (orden "visual")
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, width: usize, height: usize, bg: Color) !Framebuffer {
        const pixels = try allocator.alloc(u8, width * height * 3);
        var fb = Framebuffer{
            .width = width,
            .height = height,
            .pixels = pixels,
            .allocator = allocator,
        };
        fb.clear(bg);
        return fb;
    }

    pub fn deinit(self: *Framebuffer) void {
        self.allocator.free(self.pixels);
    }

    pub fn clear(self: *Framebuffer, color: Color) void {
        var i: usize = 0;
        while (i < self.width * self.height) : (i += 1) {
            self.pixels[i * 3 + 0] = color.r;
            self.pixels[i * 3 + 1] = color.g;
            self.pixels[i * 3 + 2] = color.b;
        }
    }

    /// Pinta un pixel individual. Ignora silenciosamente coordenadas
    /// fuera del lienzo.
    pub fn setPixel(self: *Framebuffer, x: i64, y: i64, color: Color) void {
        if (x < 0 or y < 0) return;
        const xu: usize = @intCast(x);
        const yu: usize = @intCast(y);
        if (xu >= self.width or yu >= self.height) return;

        const idx = (yu * self.width + xu) * 3;
        self.pixels[idx + 0] = color.r;
        self.pixels[idx + 1] = color.g;
        self.pixels[idx + 2] = color.b;
    }

    /// Construye los bytes completos de un archivo .bmp (header + píxeles,
    /// con padding y orden bottom-up) y los escribe en `path`.
    pub fn writeBmp(self: *Framebuffer, io: std.Io, path: []const u8) !void {
        const row_size_unpadded = self.width * 3;
        const padding: usize = (4 - (row_size_unpadded % 4)) % 4;
        const row_size_padded = row_size_unpadded + padding;

        const pixel_data_size = row_size_padded * self.height;
        const file_size = 54 + pixel_data_size;

        var buf = try self.allocator.alloc(u8, file_size);
        defer self.allocator.free(buf);

        // ---- BITMAPFILEHEADER (14 bytes) ----
        buf[0] = 'B';
        buf[1] = 'M';
        writeU32LE(buf[2..6], @intCast(file_size));
        writeU32LE(buf[6..10], 0);
        writeU32LE(buf[10..14], 54);

        // ---- BITMAPINFOHEADER (40 bytes) ----
        writeU32LE(buf[14..18], 40);
        writeI32LE(buf[18..22], @intCast(self.width));
        writeI32LE(buf[22..26], @intCast(self.height)); // positivo = bottom-up
        writeU16LE(buf[26..28], 1);
        writeU16LE(buf[28..30], 24);
        writeU32LE(buf[30..34], 0);
        writeU32LE(buf[34..38], @intCast(pixel_data_size));
        writeI32LE(buf[38..42], 2835);
        writeI32LE(buf[42..46], 2835);
        writeU32LE(buf[46..50], 0);
        writeU32LE(buf[50..54], 0);

        // ---- Datos de píxeles (bottom-up, BGR) ----
        var offset: usize = 54;
        var y: usize = self.height;
        while (y > 0) {
            y -= 1;
            var x: usize = 0;
            while (x < self.width) : (x += 1) {
                const idx = (y * self.width + x) * 3;
                buf[offset + 0] = self.pixels[idx + 2]; // B
                buf[offset + 1] = self.pixels[idx + 1]; // G
                buf[offset + 2] = self.pixels[idx + 0]; // R
                offset += 3;
            }
            var p: usize = 0;
            while (p < padding) : (p += 1) {
                buf[offset] = 0;
                offset += 1;
            }
        }

        // ---- Escribir a disco (API de Zig 0.16) ----
        const file = try std.Io.Dir.cwd().createFile(io, path, .{});
        defer file.close(io);

        var write_buf: [4096]u8 = undefined;
        var file_writer = file.writer(io, &write_buf);
        try file_writer.interface.writeAll(buf);
        try file_writer.interface.flush();
    }
};

fn writeU32LE(dest: []u8, value: u32) void {
    dest[0] = @truncate(value);
    dest[1] = @truncate(value >> 8);
    dest[2] = @truncate(value >> 16);
    dest[3] = @truncate(value >> 24);
}

fn writeI32LE(dest: []u8, value: i32) void {
    writeU32LE(dest, @bitCast(value));
}

fn writeU16LE(dest: []u8, value: u16) void {
    dest[0] = @truncate(value);
    dest[1] = @truncate(value >> 8);
}
