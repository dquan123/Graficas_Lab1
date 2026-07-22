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

    /// Dibuja una línea recta entre dos puntos usando el algoritmo de Bresenham.
    pub fn drawLine(self: *Framebuffer, x0: i64, y0: i64, x1: i64, y1: i64, color: Color) void {
        var x = x0;
        var y = y0;

        const dx: i64 = @intCast(@abs(x1 - x0));
        const dy: i64 = @intCast(@abs(y1 - y0));

        const sx: i64 = if (x0 < x1) 1 else -1;
        const sy: i64 = if (y0 < y1) 1 else -1;

        var err: i64 = dx - dy;

        while (true) {
            self.setPixel(x, y, color);

            if (x == x1 and y == y1) break;

            const e2 = 2 * err;
            if (e2 > -dy) {
                err -= dy;
                x += sx;
            }
            if (e2 < dx) {
                err += dx;
                y += sy;
            }
        }
    }

    /// Dibuja el borde completo de un polígono, conectando cada vértice
    /// con el siguiente, y cerrando del último punto al primero.
    pub fn drawPolygonOutline(self: *Framebuffer, points: []const [2]i64, color: Color) void {
        var i: usize = 0;
        while (i < points.len) : (i += 1) {
            const p0 = points[i];
            const p1 = points[(i + 1) % points.len]; // el % hace que cierre el ciclo
            self.drawLine(p0[0], p0[1], p1[0], p1[1], color);
        }
    }

    /// Rellena uno o más polígonos usando scanline fill con regla par-impar.
    /// Pasar varios polígonos juntos (para el 4 con agujero) hace que
    /// el agujero quede sin pintar.
    pub fn fillPolygons(self: *Framebuffer, allocator: std.mem.Allocator, polygons: []const []const [2]i64, color: Color) !void {
        var y_min: i64 = std.math.maxInt(i64);
        var y_max: i64 = std.math.minInt(i64);
        for (polygons) |poly| {
            for (poly) |p| {
                if (p[1] < y_min) y_min = p[1];
                if (p[1] > y_max) y_max = p[1];
            }
        }

        var y = y_min;
        while (y <= y_max) : (y += 1) {
            var xs = std.ArrayList(i64).empty;
            defer xs.deinit(allocator);

            for (polygons) |poly| {
                var i: usize = 0;
                while (i < poly.len) : (i += 1) {
                    const p0 = poly[i];
                    const p1 = poly[(i + 1) % poly.len];
                    const y0 = p0[1];
                    const y1 = p1[1];

                    if (y0 == y1) continue; // aristas horizontales no aportan cruces

                    const y_lo = @min(y0, y1);
                    const y_hi = @max(y0, y1);

                    // [y_lo, y_hi) evita contar el vértice compartido dos veces
                    if (y >= y_lo and y < y_hi) {
                        const x0f: f64 = @floatFromInt(p0[0]);
                        const y0f: f64 = @floatFromInt(y0);
                        const x1f: f64 = @floatFromInt(p1[0]);
                        const y1f: f64 = @floatFromInt(y1);
                        const yf: f64 = @floatFromInt(y);

                        const xf = x0f + (yf - y0f) * (x1f - x0f) / (y1f - y0f);
                        try xs.append(allocator, @intFromFloat(@round(xf)));
                    }
                }
            }

            std.mem.sort(i64, xs.items, {}, std.sort.asc(i64));

            var idx: usize = 0;
            while (idx + 1 < xs.items.len) : (idx += 2) {
                var x = xs.items[idx];
                const x_end = xs.items[idx + 1];
                while (x <= x_end) : (x += 1) {
                    self.setPixel(x, y, color);
                }
            }
        }
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
