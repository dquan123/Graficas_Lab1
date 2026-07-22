const std = @import("std");
const bmp = @import("bmp.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var fb = try bmp.Framebuffer.init(gpa, 800, 450, .{ .r = 30, .g = 30, .b = 30 });
    defer fb.deinit();

    // Cuadrito de prueba para confirmar que setPixel funciona.
    var y: i64 = 50;
    while (y < 150) : (y += 1) {
        var x: i64 = 50;
        while (x < 150) : (x += 1) {
            fb.setPixel(x, y, .{ .r = 220, .g = 40, .b = 40 });
        }
    }

    try fb.writeBmp(io, "out.bmp");
}
