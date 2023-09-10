const std = @import("std");
const ast = @import("ast.zig");
const Allocator = std.mem.Allocator;

pub fn main() !void {

    // We need an alocator in zig
    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){};
    gpa.setRequestedMemoryLimit(1 * 1024 * 1024); // 1MB

    const allocator = gpa.allocator();

    // The filename is the first argument
    var argv = std.process.args();
    _ = argv.next(); // skip the program name
    const filePath = argv.next() orelse {
        std.debug.panic("missing filePath argument", .{});
    };

    // Open the file relative from the current directory
    const inputFile = try std.fs.cwd().openFile(filePath, .{ .mode = std.fs.File.OpenMode.read_only });
    defer inputFile.close();

    var reader = inputFile.reader();
    _ = try ast.ASTParser.parse(allocator, reader);

    // const parsedFile = try readSimple(allocator, "files/simple.json");
    // defer parsedFile.deinit();
    // const simple = parsedFile.value;
    // std.debug.print("simple {any}\n", .{simple});
}
