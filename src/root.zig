const std = @import("std");
const testing = std.testing;

test "example" {
    testing.log_level = .debug;
    std.log.debug("Hello, World!", .{});
}
