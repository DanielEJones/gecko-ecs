const std = @import("std");
const Allocator = std.mem.Allocator;
const Map = std.StringHashMapUnmanaged;

const comps = @import("components.zig");
const Erased = comps.ErasedComponentStore;
const Store = comps.ComponentStore;

pub const Archetpye = struct {
    components: Map(Erased),
    field_count: usize,
    size: usize,

    /// Create a new archetype from the given fields
    pub fn init(allocator: Allocator, fields: anytype) !Archetpye {
        var map: Map(Erased) = .{};
        errdefer map.deinit(allocator);
        var size: usize = 0;

        // try to add an empty storage for each field
        inline for (fields) |field| {
            if (@typeInfo(field) != .@"struct") {
                @compileError("The following cannot be an archetype field: " ++ @typeName(field));
            }

            size += 1;
            const erased = try Erased.init(field, allocator);
            try map.put(allocator, @typeName(field), erased);
        }

        return .{ .components = map, .field_count = size, .size = 0 };
    }

    /// Delete an archetype and it's underlying storages
    pub fn deinit(self: *Archetpye, allocator: Allocator) void {
        var components = self.components.valueIterator();
        while (components.next()) |component| component.deinit(allocator);
        self.components.deinit(allocator);
    }

    /// Add a new element to the archetype, consturcted from the given fields
    pub fn add(self: *Archetpye, allocator: Allocator, fields: anytype) !void {
        var count: usize = 0;

        // if for whatever reason we error out, go through and strip
        // any changes we may have made.
        errdefer {
            var iter = self.components.valueIterator();
            while (iter.next()) |entry| entry.remove(self.size);
        }

        // go through each field
        inline for (fields) |field| {
            const field_type = @TypeOf(field);
            const field_name = @typeName(field_type);

            // add the fields to the correct storage
            if (self.components.getPtr(field_name)) |store| {
                var storage = store.as(field_type);
                try storage.add(allocator, field);
            } else return error.UnrecognisedField;

            count += 1;
        }

        if (count != self.components.count()) return error.MissingFields;
        self.size += 1;
    }
};

// +----------------------------------------------------------------------------------------------
// | Tests
// +

const Position = struct { x: f32, y: f32 };
const Velocity = struct { vx: f32, vy: f32 };

const expect = std.testing.expect;
const fails = std.testing.expectError;

// +-- Archetype Tests ---------------------------------------------------------------------------

test "archetpye can be created" {
    // make an allocator for the test
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var arch = try Archetpye.init(alloc, .{ Position, Velocity });
    defer arch.deinit(alloc);

    { // add a position and a velocity
        var position = arch.components.get(@typeName(Position)).?;
        try position.as(Position).add(alloc, Position{ .x = 10, .y = 11 });

        var velocity = arch.components.get(@typeName(Velocity)).?;
        try velocity.as(Velocity).add(alloc, Velocity{ .vx = 12, .vy = 13 });
    }

    { // assert that the positions stick
        var position = arch.components.get(@typeName(Position)).?;
        try expect(position.as(Position).get(0).?.x == 10);
        try expect(position.as(Position).get(0).?.y == 11);

        var velocity = arch.components.get(@typeName(Velocity)).?;
        try expect(velocity.as(Velocity).get(0).?.vx == 12);
        try expect(velocity.as(Velocity).get(0).?.vy == 13);
    }
}

test "adding new elements works" {
    // make an allocator for the test
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var arch = try Archetpye.init(alloc, .{ Position, Velocity });
    defer arch.deinit(alloc);

    std.testing.log_level = .debug;

    { // adding valid elements should succeed.
        try arch.add(alloc, .{ Position{ .x = 10, .y = 11 }, Velocity{ .vx = 12, .vy = 13 } });

        try expect(arch.size == 1);

        var position = arch.components.get(@typeName(Position)).?;
        try expect(position.as(Position).get(0).?.x == 10);
        try expect(position.as(Position).get(0).?.y == 11);

        var velocity = arch.components.get(@typeName(Velocity)).?;
        try expect(velocity.as(Velocity).get(0).?.vx == 12);
        try expect(velocity.as(Velocity).get(0).?.vy == 13);
    }

    { // adding invalid elements should fail.
        try fails(error.MissingFields, arch.add(alloc, .{Position{ .x = 14, .y = 15 }}));

        try expect(arch.size == 1);

        var position = arch.components.get(@typeName(Position)).?;
        try expect(position.as(Position).get(1) == null);

        const Bad = struct { wrong: u32 };
        try fails(
            error.UnrecognisedField,
            arch.add(alloc, .{ Position{ .x = 16, .y = 17 }, Bad{ .wrong = 0 } }),
        );

        try expect(arch.size == 1);
        try expect(position.as(Position).get(1) == null);
    }
}
