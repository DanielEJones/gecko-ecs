const std = @import("std");
const Map = std.AutoHashMapUnmanaged;
const StringMap = std.StringHashMapUnmanaged;
const Allocator = std.mem.Allocator;

const arc = @import("archetypes.zig");
const Archetype = arc.Archetype;

const EntityIndex = struct {
    arch: u128,
    index: usize,
};

const World = struct {
    archs: Map(u128, *Archetype),
    components: ComponentRegistry,

    pub fn init() World {
        return .{ .archs = .{}, .components = ComponentRegistry.init() };
    }

    pub fn deinit(self: *World, allocator: Allocator) void {
        // run through each archetype and clear it
        var arch_iter = self.archs.valueIterator();
        while (arch_iter.next()) |a| {
            a.*.deinit(allocator);
            allocator.destroy(a.*);
        }

        // clear the data structures
        self.archs.deinit(allocator);
        self.components.deinit(allocator);
    }

    pub fn new(self: *World, allocator: Allocator, value: anytype) !EntityIndex {
        const arch_index = try self.components.registerArchetype(allocator, value);

        // get the archetype or create it
        const arch = self.archs.get(arch_index) orelse get_arch: {
            const arch = try allocator.create(Archetype);
            arch.* = try Archetype.init(allocator, value);

            try self.archs.put(allocator, arch_index, arch);
            break :get_arch self.archs.get(arch_index).?;
        };

        const index = arch.size;
        try arch.add(allocator, value);

        return .{ .arch = arch_index, .index = index };
    }

    pub fn view(self: World, comptime T: anytype) arc.ArchetypeIterator(T) {
        return arc.ArchetypeIterator(T).init(self.archs.getIndex());
    }
};

const ComponentRegistry = struct {
    components: StringMap(u7),
    next_index: u7,

    /// Create a new component registry
    pub fn init() ComponentRegistry {
        return .{ .components = .{}, .next_index = 0 };
    }

    /// Destroy a component registry
    pub fn deinit(self: *ComponentRegistry, allocator: Allocator) void {
        self.components.deinit(allocator);
    }

    /// Registers a component and returns the index it is stored in
    pub fn registerComponent(self: *ComponentRegistry, allocator: Allocator, comptime T: type) !u128 {
        if (self.components.get(@typeName(T))) |_| return error.ComponentAlreadyExists;
        if (self.next_index >= 128) return error.MaxComponentsReached;

        const id = self.next_index;
        self.next_index += 1;

        try self.components.put(allocator, @typeName(T), id);
        return @as(u128, 1) << id;
    }

    /// Get a component's index from the registry if it exists, else null
    pub fn getComponent(self: *ComponentRegistry, comptime T: type) ?u128 {
        if (self.components.get(@typeName(T))) |value| {
            return @as(u128, 1) << value;
        }

        return null;
    }

    /// Get the combined index of all the components if they all exist, else null
    pub fn getArchetype(self: *ComponentRegistry, fields: anytype) ?u128 {
        var result: u128 = 0;

        inline for (fields) |field| {
            const T = if (@typeInfo(@TypeOf(field)) == .type) field else @TypeOf(field);
            result |= self.getComponent(T) orelse return null;
        }

        return result;
    }

    /// Ensure all components are registered and returned their combined index
    pub fn registerArchetype(self: *ComponentRegistry, allocator: Allocator, fields: anytype) !u128 {
        var result: u128 = 0;

        inline for (fields) |field| {
            const T = if (@typeInfo(@TypeOf(field)) == .type) field else @TypeOf(field);
            const id = self.getComponent(T) orelse try self.registerComponent(allocator, T);
            result |= id;
        }

        return result;
    }
};

// +----------------------------------------------------------------------------------------------
// | Tests
// +

const Position = struct { x: f32, y: f32 };
const Velocity = struct { vx: f32, vy: f32 };
const Health = struct { value: u8 };

const expect = std.testing.expect;
const fails = std.testing.expectError;

// +-- Test Component Registry -------------------------------------------------------------------

test "component registry register works" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var registry = ComponentRegistry.init();
    defer registry.deinit(alloc);

    { // test adding a new item
        const result = try registry.registerComponent(alloc, Position);
        try expect(result == 1);
    }

    { // test getting an old item
        try fails(error.ComponentAlreadyExists, registry.registerComponent(alloc, Position));
    }
}

test "component regisrty get works" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var registry = ComponentRegistry.init();
    defer registry.deinit(alloc);

    _ = try registry.registerComponent(alloc, Position);
    try expect(registry.getComponent(Position).? == 1);
}

test "get archetype works" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var registry = ComponentRegistry.init();
    defer registry.deinit(alloc);

    const p = try registry.registerComponent(alloc, Position);
    const v = try registry.registerComponent(alloc, Velocity);
    const h = try registry.registerComponent(alloc, Health);

    { // should sum component ids
        const result = registry.getArchetype(.{ Position, Velocity }).?;
        try expect(result == (p | v));
    }

    { // should be order-independent
        const result = registry.getArchetype(.{ Health, Position, Velocity });
        try expect(result == (p | v | h));
    }

    { // should fail if archetype contains an unknown component
        try expect(registry.getArchetype(.{ Position, struct { f32, u12 } }) == null);
    }
}

test "register archetype works" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var register = ComponentRegistry.init();
    defer register.deinit(alloc);

    try expect(try register.registerArchetype(alloc, .{ Position, Velocity }) == 3);
    try expect(try register.registerArchetype(alloc, .{ Position, Health }) == 5);
}

// +-- Test World --------------------------------------------------------------------------------

test "can add to world" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();
    defer _ = gpa.deinit();

    var world = World.init();
    defer world.deinit(alloc);

    { // create the first one
        const id = try world.new(alloc, .{
            Position{ .x = 10, .y = 11 },
            Velocity{ .vx = 0.5, .vy = 100 },
        });
        try expect(id.arch == 3 and id.index == 0);
    }

    { // create the second one
        const id = try world.new(alloc, .{
            Position{ .x = 11, .y = 12 },
            Velocity{ .vx = 1.5, .vy = 101 },
        });
        try expect(id.arch == 3 and id.index == 1);
    }

    { // create a different archetype
        const id = try world.new(alloc, .{
            Position{ .x = 12, .y = 13 },
            Health{ .value = 19 },
        });
        try expect(id.arch == 5 and id.index == 0);
    }

    { // make a big, out-of-order one
        const id = try world.new(alloc, .{
            Velocity{ .vx = 999, .vy = -999 },
            Health{ .value = 10 },
            Position{ .x = 14, .y = 15 },
        });
        try expect(id.arch == 7 and id.index == 0);
    }
}
