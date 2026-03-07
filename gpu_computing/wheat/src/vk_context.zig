const std = @import("std");
const vk = @import("vulkan");

/// Wrappers provided by 'vulkan-zig' to handle function pointer loading.
/// Vulkan functions are not static; they must be loaded from the driver at runtime.
const BaseDispatch = vk.BaseWrapper; // Loads global functions (vkCreateInstance)
const InstanceDispatch = vk.InstanceWrapper; // Loads instance functions (vkEnumeratePhysicalDevices)
const DeviceDispatch = vk.DeviceWrapper; // Loads device functions (vkDispatch, vkBindPipeline)

/// Main Context struct holding the GPU state.
/// This manages the lifecycle of the Vulkan application.
pub const VulkanContext = struct {
    /// Handle to the loaded dynamic library
    lib: std.DynLib,

    instance: vk.Instance,
    pdev: vk.PhysicalDevice, // physical
    dev: vk.Device, // logical
    queue: vk.Queue, // work queue
    q_fam: u32, // family index of queue

    /// Dispatch tables containing the actual function pointers
    bk: BaseDispatch,
    ins: InstanceDispatch,
    dev_d: DeviceDispatch,

    /// Memory properties of the GPU (used to find Host-Visible RAM)
    mem_props: vk.PhysicalDeviceMemoryProperties,

    /// Initialize Vulkan specifically for Compute operations.
    /// This skips graphics-specific steps (Swapchain, Surface) for efficiency.
    pub fn init(allocator: std.mem.Allocator, app_name: [*:0]const u8) !VulkanContext {
        // Load Vulkan shader lib
        const lib_name = if (@import("builtin").os.tag == .windows) "vulkan-1.dll" else "libvulkan.so.1";
        var lib = try std.DynLib.open(lib_name);
        const vk_proc = lib.lookup(vk.PfnGetInstanceProcAddr, "vkGetInstanceProcAddr") orelse {
            return error.MissingVkGetInstanceProcAddr;
        };
        // Load the "Entry Point" function
        const bk = BaseDispatch.load(vk_proc);

        // Create Vulkan instance
        // We request API version 1.2 for stability
        const app_info = vk.ApplicationInfo{
            .p_application_name = app_name,
            .application_version = 0,
            .p_engine_name = app_name,
            .engine_version = 0,
            .api_version = @bitCast(vk.API_VERSION_1_2),
        };
        const instance = try bk.createInstance(&.{ .p_application_info = &app_info }, null);
        const vki = InstanceDispatch.load(instance, bk.dispatch.vkGetInstanceProcAddr.?);

        // --- 1. Enumerate All GPUs ---
        var gpu_count: u32 = 0;
        _ = try vki.enumeratePhysicalDevices(instance, &gpu_count, null);
        const gpus = try allocator.alloc(vk.PhysicalDevice, gpu_count);
        defer allocator.free(gpus);
        _ = try vki.enumeratePhysicalDevices(instance, &gpu_count, gpus.ptr);

        // --- 2. Smart Device Selection ---
        // We will loop through all GPUs and look for a DISCRETE_GPU (dedicated card).
        var selected_pdev: vk.PhysicalDevice = .null_handle;
        var selected_props: vk.PhysicalDeviceProperties = undefined;
        var found_discrete = false;

        std.debug.print("Available GPUs:\n", .{});

        for (gpus) |gpu| {
            const props = vki.getPhysicalDeviceProperties(gpu);
            std.debug.print("  - {s} ({s})\n", .{ props.device_name, @tagName(props.device_type) });

            // Criteria 1: Must support our required Queue (Compute)
            if (!try checkComputeQueueSupport(allocator, vki, gpu)) continue;

            // Criteria 2: Prefer Discrete GPU
            if (props.device_type == .discrete_gpu) {
                selected_pdev = gpu;
                selected_props = props;
                found_discrete = true;
                // If we found a dedicated card, stop looking (or you could score them further)
                break;
            }

            // Fallback: If we haven't found a discrete one yet, keep this one (e.g. integrated)
            if (selected_pdev == .null_handle) {
                selected_pdev = gpu;
                selected_props = props;
            }
        }

        if (selected_pdev == .null_handle) return error.NoSuitableGPU;
        std.debug.print(">> Selected GPU: {s}\n", .{selected_props.device_name});

        // --- 3. Queue Family Search (Recalculate for the selected device) ---
        // We technically checked this above, but we need the index now.
        const q_fam = try findComputeQueueFamily(allocator, vki, selected_pdev);

        // Create logical device
        // We MUST enable 'shaderInt64' feature for the Minecraft math to work.
        const priority = [_]f32{1.0};
        const q_info = vk.DeviceQueueCreateInfo{
            .queue_family_index = q_fam,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        };

        // 'shader_int_64' allows using int64_t in GLSL.
        // Note: Field name depends on vulkan-zig generation (check vk.zig if error).
        var features = vk.PhysicalDeviceFeatures{ .shader_int_64 = .true };
        const device = try vki.createDevice(selected_pdev, &.{
            .queue_create_info_count = 1,
            .p_queue_create_infos = @ptrCast(&q_info),
            .p_enabled_features = &features,
        }, null);

        const vkd = DeviceDispatch.load(device, vki.dispatch.vkGetDeviceProcAddr.?);
        const queue = vkd.getDeviceQueue(device, q_fam, 0);

        return VulkanContext{
            .lib = lib,
            .instance = instance,
            .pdev = selected_pdev,
            .dev = device,
            .queue = queue,
            .q_fam = q_fam,
            .bk = bk,
            .ins = vki,
            .dev_d = vkd,
            .mem_props = vki.getPhysicalDeviceMemoryProperties(selected_pdev),
        };
    }

    fn checkComputeQueueSupport(allocator: std.mem.Allocator, vki: InstanceDispatch, pdev: vk.PhysicalDevice) !bool {
        const index = findComputeQueueFamily(allocator, vki, pdev) catch return false;
        _ = index;
        return true;
    }

    fn findComputeQueueFamily(allocator: std.mem.Allocator, vki: InstanceDispatch, pdev: vk.PhysicalDevice) !u32 {
        var q_count: u32 = 0;
        vki.getPhysicalDeviceQueueFamilyProperties(pdev, &q_count, null);
        const q_props = try allocator.alloc(vk.QueueFamilyProperties, q_count);
        defer allocator.free(q_props);
        vki.getPhysicalDeviceQueueFamilyProperties(pdev, &q_count, q_props.ptr);

        for (q_props, 0..) |prop, i| {
            if (prop.queue_flags.compute_bit) {
                return @intCast(i);
            }
        }
        return error.NoComputeQueue;
    }

    pub fn deinit(self: *VulkanContext) void {
        self.dev_d.destroyDevice(self.dev, null);
        self.ins.destroyInstance(self.instance, null);
        self.lib.close();
    }
};
