const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn ComponentStore(comptime T: type) type {
    return struct {
        data: std.ArrayListUnmanaged(T),
        size: usize,

        pub fn init() ComponentStore(T) {
            return .{ .data = .{}, .size = 0 };
        }

        pub fn deinit(self: *ComponentStore(T), allocator: Allocator) void {
            self.data.deinit(allocator);
        }

        pub fn add(self: *ComponentStore(T), allocator: Allocator, item: T) void {
            self.data.append(allocator, item) catch @panic("Ran out of memory!");
            self.size += 1;
        }

        pub fn get(self: *ComponentStore(T), index: usize) ?*T {
            if (index >= self.size) return null;
            return &self.data.items[index];
        }

        pub fn remove(self: *ComponentStore(T), index: usize) void {
            _ = self.data.swapRemove(index);
            self.size -= 1;
        }
    };
}

test "can add components" {
    const Position = struct { x: f32, y: f32 };

    // make an allocator to run the test with
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var store = ComponentStore(Position).init();
    defer store.deinit(alloc);

    // Adding should increase size
    store.add(alloc, Position{ .x = 10, .y = 10 });
    try std.testing.expect(store.size == 1);
}

test "can get components" {
    const Position = struct { x: f32, y: f32 };

    // make an allocator to run the test with
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var store = ComponentStore(Position).init();
    defer store.deinit(alloc);

    store.add(alloc, Position{ .x = 10, .y = 10 });

    // getting an existing index should return the component
    const should_exist = store.get(0);
    try std.testing.expect(should_exist != null);
    try std.testing.expect(should_exist.?.x == 10);
    try std.testing.expect(should_exist.?.y == 10);

    // getting an index to large should return null
    const should_be_null = store.get(10);
    try std.testing.expect(should_be_null == null);
}

test "can remove components" {
    const Position = struct { x: f32, y: f32 };

    // make an allocator to run the test with
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var store = ComponentStore(Position).init();
    defer store.deinit(alloc);

    store.add(alloc, Position{ .x = 10, .y = 10 });
    store.add(alloc, Position{ .x = 11, .y = 11 });
    store.add(alloc, Position{ .x = 12, .y = 12 });

    // removing an item should swap with the last element
    store.remove(0);
    try std.testing.expect(store.size == 2);
    try std.testing.expect(store.get(0).?.x == 12);
}
