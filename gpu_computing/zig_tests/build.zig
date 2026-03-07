const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const vulkan_zig_dep = b.dependency("vulkan_zig", .{});
    const vulkan_headers_dep = b.dependency("vulkan_headers", .{});
    const registry_path = vulkan_headers_dep.path("registry/vk.xml");

    const gen_step = b.addRunArtifact(vulkan_zig_dep.artifact("vulkan-zig-generator"));
    // tell the generator where to find vk.xml and where to output vk.zig
    gen_step.addFileArg(registry_path);
    const vk_zig_file = gen_step.addOutputFileArg("vk.zig");
    const vk_module = b.addModule("vulkan", .{
        .root_source_file = vk_zig_file,
    });

    const exe = b.addExecutable(.{
        .name = "zig_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("vulkan", vk_module);

    // libc is required for SDL/Vulkan interaction
    exe.linkLibC();
    // link system libs
    // this will not work on Windows btw
    exe.linkSystemLibrary("SDL2");
    // vulkan-zig loads functions dynamically, but we still often need
    // to link the vulkan loader for the initial entry point.
    exe.linkSystemLibrary("vulkan");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
