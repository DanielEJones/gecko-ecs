const player = world.new(.{
    Position{ .x = 10, .y = 10 },
    Velocity{ .vx = -1, .vy = 0 },
});

{ // edit components manually
    const v = world.getComponent(player, Velocty);
    var p = world.getComponent(player, Position);

    p.x += v.vx;
    p.y += v.vy;
}

{ // edit components through views
    var it = world.view(struct { p: *Position, v: Velocity });
    while (it.next()) |e| {
        e.p.x += e.v.vx;
        e.p.y += e.v.vy;
    }
}

// edit components through systems
fn moveAll(query: Query(struct { p: *Position, v: Velocity })) {
    while (query.next()) |e| {
        e.p.x += e.v.vx;
        e.p.y += e.v.vy;
    }
}

world.registerSystem(moveAll);

while (true) {
    // runs all the systems
    world.step();
}
