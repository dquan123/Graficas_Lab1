const std = @import("std");
const bmp = @import("bmp.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var fb = try bmp.Framebuffer.init(gpa, 800, 450, .{ .r = 245, .g = 245, .b = 245 });
    defer fb.deinit();

    const poligono1 = [_][2]i64{
        .{ 165, 380 }, .{ 185, 360 }, .{ 180, 330 }, .{ 207, 345 }, .{ 233, 330 },
        .{ 230, 360 }, .{ 250, 380 }, .{ 220, 385 }, .{ 205, 410 }, .{ 193, 383 },
    };

    const poligono2 = [_][2]i64{
        .{ 321, 335 }, .{ 288, 286 }, .{ 339, 251 }, .{ 374, 302 },
    };

    const poligono3 = [_][2]i64{
        .{ 377, 249 }, .{ 411, 197 }, .{ 436, 249 },
    };

    const poligono4 = [_][2]i64{
        .{ 413, 177 }, .{ 448, 159 }, .{ 502, 88 },  .{ 553, 53 },  .{ 535, 36 },
        .{ 676, 37 },  .{ 660, 52 },  .{ 750, 145 }, .{ 761, 179 }, .{ 672, 192 },
        .{ 659, 214 }, .{ 615, 214 }, .{ 632, 230 }, .{ 580, 230 }, .{ 597, 215 },
        .{ 552, 214 }, .{ 517, 144 }, .{ 466, 180 },
    };

    const poligono5 = [_][2]i64{
        .{ 682, 175 }, .{ 708, 120 }, .{ 735, 148 }, .{ 739, 170 },
    };

    // Colores de línea distintos por polígono, solo para distinguirlos
    // visualmente en esta prueba.
    try fb.fillPolygons(gpa, &.{&poligono1}, .{ .r = 77, .g = 214, .b = 214 });
    fb.drawPolygonOutline(&poligono1, .{ .r = 36, .g = 36, .b = 36 });

    try fb.fillPolygons(gpa, &.{&poligono2}, .{ .r = 77, .g = 214, .b = 214 });
    fb.drawPolygonOutline(&poligono2, .{ .r = 36, .g = 36, .b = 36 });

    try fb.fillPolygons(gpa, &.{&poligono3}, .{ .r = 77, .g = 214, .b = 214 });
    fb.drawPolygonOutline(&poligono3, .{ .r = 36, .g = 36, .b = 36 });

    try fb.fillPolygons(gpa, &.{ &poligono4, &poligono5 }, .{ .r = 77, .g = 214, .b = 214 });
    fb.drawPolygonOutline(&poligono4, .{ .r = 36, .g = 36, .b = 36 });
    fb.drawPolygonOutline(&poligono5, .{ .r = 224, .g = 30, .b = 22 });

    try fb.writeBmp(io, "out.bmp");
}
