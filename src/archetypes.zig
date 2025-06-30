const std = @import("std");
const Allocator = std.mem.Allocator;
const Map = std.StringHashMapUnmanaged;

const comps = @import("components.zig");
const Erased = comps.ErasedComponentStore;
const Store = comps.ComponentStore;

pub const Archetype = struct {
    components: Map(Erased),
    field_count: usize,
    size: usize,

    /// Create a new archetype from the given fields
    pub fn init(allocator: Allocator, fields: anytype) !Archetype {
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
    pub fn deinit(self: *Archetype, allocator: Allocator) void {
        var components = self.components.valueIterator();
        while (components.next()) |component| component.deinit(allocator);
        self.components.deinit(allocator);
    }

    /// Add a new element to the archetype, consturcted from the given fields
    pub fn add(self: *Archetype, allocator: Allocator, fields: anytype) !void {
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

    /// Get an iterator over a subset of the components
    pub fn view(self: *Archetype, comptime T: type) !ArchetypeIterator(T) {
        // ensure that all the fields actually exist
        inline for (@typeInfo(T).@"struct".fields) |field| {
            switch (@typeInfo(field.type)) {
                .pointer => |ptr| {
                    if (self.components.get(@typeName(ptr.child)) == null)
                        return error.FieldNotFound;
                },
                .@"struct" => {
                    if (self.components.get(@typeName(field.type)) == null)
                        return error.FieldNotFound;
                },
                else => {},
            }
        }

        return ArchetypeIterator(T).init(self);
    }
};

pub fn ArchetypeIterator(comptime T: type) type {
    return struct {
        archetype: *Archetype,
        index: usize,

        pub fn init(archetype: *Archetype) ArchetypeIterator(T) {
            return .{ .archetype = archetype, .index = 0 };
        }

        pub fn next(self: *ArchetypeIterator(T)) ?T {
            if (self.index >= self.archetype.size) return null;

            var result: T = undefined;

            inline for (@typeInfo(T).@"struct".fields) |field| {
                switch (@typeInfo(field.type)) {
                    .pointer => |ptr| {
                        const Underlying = ptr.child;
                        var store = self.archetype.components.get(@typeName(Underlying)).?;
                        @field(result, field.name) = store.as(Underlying).get(self.index).?;
                    },

                    .@"struct" => {
                        var store = self.archetype.components.get(@typeName(field.type)).?;
                        @field(result, field.name) = store.as(field.type).get(self.index).?.*;
                    },

                    else => {},
                }
            }

            self.index += 1;
            return result;
        }
    };
}

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

    var arch = try Archetype.init(alloc, .{ Position, Velocity });
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

    var arch = try Archetype.init(alloc, .{ Position, Velocity });
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

// +-- Archetype Iterator Tests ------------------------------------------------------------------

test "can iterate over component" {
    // make an allocator to test with
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var moveable = try Archetype.init(alloc, .{ Position, Velocity });
    defer moveable.deinit(alloc);

    try moveable.add(alloc, .{ Position{ .x = 10, .y = 11 }, Velocity{ .vx = 12, .vy = 13 } });
    try moveable.add(alloc, .{ Position{ .x = 14, .y = 15 }, Velocity{ .vx = 16, .vy = 17 } });
    try moveable.add(alloc, .{ Position{ .x = 18, .y = 19 }, Velocity{ .vx = 20, .vy = 21 } });

    var it = try moveable.view(struct { p: *Position, v: Velocity });

    try expect(it.next().?.p.x == 10);
    try expect(it.next().?.v.vx == 16);
    try expect(it.next().?.p.y == 19);
    try expect(it.next() == null);
}

test "iterators can fail" {
    // make an allocator to test with
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var moveable = try Archetype.init(alloc, .{ Position, Velocity });
    defer moveable.deinit(alloc);

    const T = struct { bad: u8 };
    try fails(error.FieldNotFound, moveable.view(struct { bad: T }));
}
