const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn ComponentStore(comptime T: type) type {
    return struct {
        data: std.ArrayListUnmanaged(T),
        size: usize,

        /// Create a Component Store
        pub fn init() ComponentStore(T) {
            return .{ .data = .{}, .size = 0 };
        }

        /// Delete a Component Store
        pub fn deinit(self: *ComponentStore(T), allocator: Allocator) void {
            self.data.deinit(allocator);
        }

        /// Add a new element to the Component Store
        pub fn add(self: *ComponentStore(T), allocator: Allocator, item: T) !void {
            try self.data.append(allocator, item);
            self.size += 1;
        }

        /// Returns an optional pointer to a given index
        pub fn get(self: *ComponentStore(T), index: usize) ?*T {
            if (index >= self.size) return null;
            return &self.data.items[index];
        }

        /// Removes a given index by swapping it with the last index
        pub fn remove(self: *ComponentStore(T), index: usize) void {
            _ = self.data.swapRemove(index);
            self.size -= 1;
        }
    };
}

pub const ErasedComponentStore = struct {
    ptr: *anyopaque,
    vtable: ComponentMethods,

    /// Create an Erased Store of the underlying type
    pub fn init(comptime T: type, allocator: Allocator) !ErasedComponentStore {
        const store = try allocator.create(ComponentStore(T));
        store.* = ComponentStore(T).init();
        return .{
            .ptr = store,
            .vtable = ComponentMethods.make(T),
        };
    }

    /// Destroy an Erased Store and it's underlying storage
    pub fn deinit(self: *ErasedComponentStore, allocator: Allocator) void {
        self.vtable.deinit(self.ptr, allocator);
    }

    /// Cast the underlying store to the given type
    pub fn as(self: *ErasedComponentStore, comptime T: type) *ComponentStore(T) {
        // both the following compiler intrinsics cast based on the
        // types it can infer, which in this case is the return type
        // of the function.
        return @ptrCast(@alignCast(self.ptr));
    }
};

const ComponentMethods = struct {
    deinit: *const fn (*anyopaque, Allocator) void,

    /// Returns a method vtable for a given component type
    pub fn make(comptime T: type) ComponentMethods {
        // Since we can't define anonymous functions, we'll instead
        // put all of the vtable methods in this struct and return
        // their reference instead.
        const fns = struct {
            fn deinit(ptr: *anyopaque, alloc: Allocator) void {
                const store: *ComponentStore(T) = @ptrCast(@alignCast(ptr));
                store.deinit(alloc);
                alloc.destroy(store);
            }
        };

        return .{ .deinit = fns.deinit };
    }
};

// +----------------------------------------------------------------------------------------------
// | Tests
// +

const expect = std.testing.expect;
const Position = struct { x: f32, y: f32 };

// +-- Component Store ---------------------------------------------------------------------------

test "can add components" {
    // make an allocator to run the test with
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var store = ComponentStore(Position).init();
    defer store.deinit(alloc);

    // Adding should increase size
    try store.add(alloc, Position{ .x = 10, .y = 10 });
    try expect(store.size == 1);
}

test "can get components" {
    // make an allocator to run the test with
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var store = ComponentStore(Position).init();
    defer store.deinit(alloc);

    try store.add(alloc, Position{ .x = 10, .y = 10 });

    // getting an existing index should return the component
    const should_exist = store.get(0);
    try expect(should_exist != null);
    try expect(should_exist.?.x == 10);
    try expect(should_exist.?.y == 10);

    // getting an index to large should return null
    const should_be_null = store.get(10);
    try expect(should_be_null == null);
}

test "can remove components" {
    // make an allocator to run the test with
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var store = ComponentStore(Position).init();
    defer store.deinit(alloc);

    try store.add(alloc, Position{ .x = 10, .y = 10 });
    try store.add(alloc, Position{ .x = 11, .y = 11 });
    try store.add(alloc, Position{ .x = 12, .y = 12 });

    // removing an item should swap with the last element
    store.remove(0);
    try expect(store.size == 2);
    try expect(store.get(0).?.x == 12);
}

// +-- Erased Component Store --------------------------------------------------------------------

test "casting works correctly" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var erased = try ErasedComponentStore.init(Position, alloc);
    defer erased.deinit(alloc);

    var first_access = erased.as(Position);
    try first_access.add(alloc, Position{ .x = 10, .y = 10 });

    const second_access = erased.as(Position);
    try expect(second_access.size == 1);
}
