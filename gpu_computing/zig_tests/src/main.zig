const std = @import("std");
const vk = @import("vulkan");

const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_vulkan.h");
});

// 1. Define Feature Sets (Keep these for the Proxies)
const instance_features = &.{
    vk.features.version_1_0,
    vk.features.base_version_1_0,
    vk.extensions.khr_surface,
};

const device_features = &.{
    vk.features.version_1_0,
    vk.extensions.khr_swapchain,
};

const SwapChainSupportDetails = struct {
    capabilities: vk.SurfaceCapabilitiesKHR,
    formats: []vk.SurfaceFormatKHR,
    present_modes: []vk.PresentModeKHR,
};

// 2. Proxies (We keep these!)
const InstanceDispatch = vk.InstanceWrapper(instance_features);
const InstanceProxy = vk.InstanceProxy(instance_features);
const DeviceDispatch = vk.DeviceWrapper(device_features);
const DeviceProxy = vk.DeviceProxy(device_features);

pub fn main() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) return error.SDLInitFailed;
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow(
        "Zig + Vulkan (Hybrid Bootstrap)",
        c.SDL_WINDOWPOS_CENTERED,
        c.SDL_WINDOWPOS_CENTERED,
        800,
        600,
        c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE,
    ) orelse return error.SDLWindowFailed;
    defer c.SDL_DestroyWindow(window);

    // --- MANUAL BOOTSTRAP START ---

    // 1. Get the SDL Loader Function
    const gdpa = c.SDL_Vulkan_GetVkGetInstanceProcAddr();
    if (gdpa == null) return error.NoVulkanLoader;
    const loader_fn = @as(vk.PfnGetInstanceProcAddr, @ptrCast(gdpa));

    // 2. Manually Load vkCreateInstance
    // We ask the loader for the function pointer by name
    const create_instance_ptr = loader_fn(.null_handle, "vkCreateInstance");
    if (create_instance_ptr == null) return error.VkCreateInstanceNotFound;

    // Cast it to the Zig function signature
    const createInstance = @as(vk.PfnCreateInstance, @ptrCast(create_instance_ptr));

    // 3. Prepare Extensions
    var ext_count: u32 = 0;
    if (c.SDL_Vulkan_GetInstanceExtensions(window, &ext_count, null) == c.SDL_FALSE) return error.NoExtensions;

    const allocator = std.heap.page_allocator;
    const ext_names = try allocator.alloc([*c]const u8, ext_count);
    defer allocator.free(ext_names);

    if (c.SDL_Vulkan_GetInstanceExtensions(window, &ext_count, ext_names.ptr) == c.SDL_FALSE) return error.NoExtensions;

    // 4. Create Instance (Calling the function pointer directly)
    const app_info = vk.ApplicationInfo{
        .p_application_name = "Zig Game",
        .application_version = vk.makeApiVersion(0, 1, 0, 0),
        .p_engine_name = "No Engine",
        .engine_version = vk.makeApiVersion(0, 1, 0, 0),
        .api_version = vk.API_VERSION_1_2,
    };

    const create_info = vk.InstanceCreateInfo{
        .p_application_info = &app_info,
        .enabled_extension_count = ext_count,
        .pp_enabled_extension_names = @ptrCast(ext_names.ptr),
        .enabled_layer_count = 0,
        .pp_enabled_layer_names = null,
    };

    var instance_handle: vk.Instance = .null_handle;
    const result = createInstance(&create_info, null, &instance_handle);
    if (result != .success) return error.VulkanInitializationFailed;

    // --- MANUAL BOOTSTRAP END ---

    // 5. Upgrade to Vulkan-Zig Proxy
    // A. Load the Dispatch Table
    const vki_dispatch = try InstanceDispatch.load(instance_handle, loader_fn);

    // B. Initialize the Proxy (Pass the pointer using '&')
    const vki = InstanceProxy.init(instance_handle, &vki_dispatch);
    defer vki.destroyInstance(null);

    std.debug.print("Success! Instance: {any}\n", .{instance_handle});

    // 6. Surface
    var c_surface: c.VkSurfaceKHR = null;
    const c_instance = @as(c.VkInstance, @ptrFromInt(@intFromEnum(instance_handle)));
    if (c.SDL_Vulkan_CreateSurface(window, c_instance, &c_surface) == c.SDL_FALSE) {
        return error.SurfaceCreationFailed;
    }
    const surface = @as(vk.SurfaceKHR, @enumFromInt(@intFromPtr(c_surface)));
    defer vki.destroySurfaceKHR(surface, null);

    std.debug.print("Surface Created!\n", .{});

    // 7. Pick GPU and Queue Families
    const gpu_info = try pickPhysicalDevice(vki, surface, allocator);
    std.debug.print("Picked GPU: {any}\n", .{gpu_info.pdev});

    // 8. Create Logical Device
    const device_setup = try createLogicalDevice(vki, gpu_info.pdev, gpu_info.indices, allocator);
    defer device_setup.vkd.destroyDevice(null);

    const vkd = device_setup.vkd;
    const graphics_queue = device_setup.graphics_queue;
    const present_queue = device_setup.present_queue;

    std.debug.print("Logical Device Created.\n", .{});

    // 9. Create Swapchain
    const swapchain_setup = try createSwapChain(
        vki,
        vkd,
        gpu_info.pdev,
        surface,
        window,
        gpu_info.indices,
        allocator,
    );
    defer vkd.destroySwapchainKHR(swapchain_setup.swapchain, null);
    defer allocator.free(swapchain_setup.images); // Free the slice storage, not the images themselves

    std.debug.print("Swapchain Created with {} images.\n", .{swapchain_setup.images.len});

    // 10. Create Image Views
    const image_views = try createImageViews(vkd, swapchain_setup.images, swapchain_setup.format, allocator);
    // Cleanup: Destroy the views when done.
    defer for (image_views) |view| vkd.destroyImageView(view, null);
    defer allocator.free(image_views);

    std.debug.print("Image Views Created: {}.\n", .{image_views.len});

    // 11. Create Render Pass
    const render_pass = try createRenderPass(vkd, swapchain_setup.format);
    defer vkd.destroyRenderPass(render_pass, null);

    std.debug.print("Render Pass Created.\n", .{});

    // 12. Placeholder for Graphics Pipeline
    // This requires Shaders, which we haven't compiled yet!

    // Main Loop...
    var running = true;
    var event: c.SDL_Event = undefined;
    while (running) {
        while (c.SDL_PollEvent(&event) != 0) {
            if (event.type == c.SDL_QUIT) running = false;
        }
        c.SDL_Delay(10); // 10 milliseconds is usually enough
    }
}

const QueueFamilyIndices = struct {
    graphics_family: ?u32 = null,
    present_family: ?u32 = null,

    fn isComplete(self: QueueFamilyIndices) bool {
        return self.graphics_family != null and self.present_family != null;
    }
};

fn findQueueFamilyIndices(
    vki: InstanceProxy,
    pdev: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
    allocator: std.mem.Allocator,
) !QueueFamilyIndices {
    var indices: QueueFamilyIndices = .{};

    // 1. Get queue family properties (type of operations supported)
    const families = try vki.getPhysicalDeviceQueueFamilyProperties(pdev, allocator);
    defer allocator.free(families);

    for (families, 0..) |family, i| {
        // A. Check for Graphics Support
        if (family.queue_flags.graphics_bit) {
            indices.graphics_family = @intCast(i);
        }

        // B. Check for Presentation Support (Specific to the surface)
        var supports_present: u32 = 0;
        const result = vki.getPhysicalDeviceSurfaceSupportKHR(pdev, @intCast(i), surface, &supports_present);
        if (result == .success and supports_present == vk.TRUE) {
            indices.present_family = @intCast(i);
        }

        if (indices.isComplete()) break;
    }

    return indices;
}

fn pickPhysicalDevice(vki: InstanceProxy, surface: vk.SurfaceKHR, allocator: std.mem.Allocator) !struct { pdev: vk.PhysicalDevice, indices: QueueFamilyIndices } {
    const pdevs = try vki.enumeratePhysicalDevices(vki.handle, allocator);
    defer allocator.free(pdevs);

    for (pdevs) |pdev| {
        const indices = try findQueueFamilyIndices(vki, pdev, surface, allocator);

        // Required Check: Does it support the Swapchain extension?
        var ext_count: u32 = 0;
        _ = vki.enumerateDeviceExtensionProperties(pdev, null, &ext_count, null);
        const available_exts = try allocator.alloc(vk.ExtensionProperties, ext_count);
        defer allocator.free(available_exts);
        _ = vki.enumerateDeviceExtensionProperties(pdev, null, &ext_count, available_exts.ptr);

        var supports_swapchain = false;
        for (available_exts) |ext| {
            if (std.mem.eql(u8, std.mem.span(ext.extension_name), vk.extensions.khr_swapchain.name)) {
                supports_swapchain = true;
                break;
            }
        }

        if (indices.isComplete() and supports_swapchain) {
            return .{ .pdev = pdev, .indices = indices };
        }
    }

    return error.NoSuitableGPUFound;
}

fn createLogicalDevice(
    vki: InstanceProxy,
    pdev: vk.PhysicalDevice,
    indices: QueueFamilyIndices,
    allocator: std.mem.Allocator,
) !struct { vkd: DeviceProxy, graphics_queue: vk.Queue, present_queue: vk.Queue } {
    const priority = [_]f32{1.0};
    const graphics_index = indices.graphics_family.?;
    const present_index = indices.present_family.?;

    // Use a hash set to ensure we only define unique queues once
    var unique_families = std.hash_map.AutoHashMap(u32, void).init(allocator);
    defer unique_families.deinit();

    try unique_families.put(graphics_index, {});
    try unique_families.put(present_index, {});

    var queue_create_infos = try allocator.alloc(vk.DeviceQueueCreateInfo, unique_families.count());
    defer allocator.free(queue_create_infos);

    var i: usize = 0;
    var families_it = unique_families.keyIterator();
    while (families_it.next()) |family_index| : (i += 1) {
        queue_create_infos[i] = vk.DeviceQueueCreateInfo{
            .queue_family_index = family_index.*,
            .queue_count = 1,
            .p_queue_priorities = &priority,
        };
    }

    // Extensions: Swapchain is mandatory here
    const device_extensions = [_][*:0]const u8{vk.extensions.khr_swapchain.name};

    const device_info = vk.DeviceCreateInfo{
        .queue_create_info_count = @intCast(queue_create_infos.len),
        .p_queue_create_infos = queue_create_infos.ptr,
        .enabled_extension_count = device_extensions.len,
        .pp_enabled_extension_names = &device_extensions,
        // .p_enabled_features = null, // Can enable features here
    };

    var device_handle: vk.Device = .null_handle;
    const result = vki.createDevice(pdev, &device_info, null, &device_handle);
    if (result != .success) return error.DeviceCreationFailed;

    // Load Device Functions and Proxy
    const vkd_dispatch = try DeviceDispatch.load(device_handle, vki.dispatch.vkGetDeviceProcAddr);
    const vkd = DeviceProxy.init(device_handle, &vkd_dispatch);

    // Get the queue handles
    var graphics_queue: vk.Queue = .null_handle;
    var present_queue: vk.Queue = .null_handle;
    vkd.getDeviceQueue(device_handle, graphics_index, 0, &graphics_queue);
    vkd.getDeviceQueue(device_handle, present_index, 0, &present_queue);

    return .{
        .vkd = vkd,
        .graphics_queue = graphics_queue,
        .present_queue = present_queue,
    };
}

fn querySwapChainSupport(
    vki: InstanceProxy,
    pdev: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
    allocator: std.mem.Allocator,
) !SwapChainSupportDetails {
    // 1. Capabilities (Min/Max image count, image size limits)
    var capabilities: vk.SurfaceCapabilitiesKHR = undefined;
    _ = vki.getPhysicalDeviceSurfaceCapabilitiesKHR(pdev, surface, &capabilities);

    // 2. Formats (Color depth, e.g., RGBA)
    var format_count: u32 = 0;
    _ = vki.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &format_count, null);
    const formats = try allocator.alloc(vk.SurfaceFormatKHR, format_count);
    _ = vki.getPhysicalDeviceSurfaceFormatsKHR(pdev, surface, &format_count, formats.ptr);

    // 3. Presentation Modes (V-Sync, etc.)
    var present_mode_count: u32 = 0;
    _ = vki.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &present_mode_count, null);
    const present_modes = try allocator.alloc(vk.PresentModeKHR, present_mode_count);
    _ = vki.getPhysicalDeviceSurfacePresentModesKHR(pdev, surface, &present_mode_count, present_modes.ptr);

    return SwapChainSupportDetails{
        .capabilities = capabilities,
        .formats = formats,
        .present_modes = present_modes,
    };
}

fn chooseSwapSurfaceFormat(available_formats: []const vk.SurfaceFormatKHR) vk.SurfaceFormatKHR {
    // Look for the ideal format: B8G8R8A8 Unorm and sRGB colorspace
    for (available_formats) |format| {
        if (format.format == vk.Format.b8g8r8a8_unorm and
            format.color_space == vk.ColorSpace.srgb_non_linear)
        {
            return format;
        }
    }
    // Fallback: If ideal is not found, take the first one available
    return available_formats[0];
}

fn chooseSwapPresentMode(available_modes: []const vk.PresentModeKHR) vk.PresentModeKHR {
    // Look for Mailbox mode (Triple Buffering, low latency, modern choice)
    for (available_modes) |mode| {
        if (mode == vk.PresentMode.mailbox_khr) {
            return mode;
        }
    }
    // Fallback: Fifo mode (Standard V-Sync, guaranteed to be available)
    return vk.PresentMode.fifo_khr;
}

fn chooseSwapExtent(capabilities: vk.SurfaceCapabilitiesKHR, window: *c.SDL_Window) vk.Extent2D {
    // If current_extent is UINT32_MAX, the window manager allows us to pick the size.
    if (capabilities.current_extent.width != std.math.maxInt(u32)) {
        return capabilities.current_extent;
    } else {
        var width: i32 = 0;
        var height: i32 = 0;

        // Get the current window size from SDL
        c.SDL_Vulkan_GetDrawableSize(window, &width, &height);

        // Clamp the extent to the min/max limits supported by the GPU
        return vk.Extent2D{
            .width = @intCast(std.math.clamp(@as(u32, @intCast(width)), capabilities.min_image_extent.width, capabilities.max_image_extent.width)),
            .height = @intCast(std.math.clamp(@as(u32, @intCast(height)), capabilities.min_image_extent.height, capabilities.max_image_extent.height)),
        };
    }
}

fn createSwapChain(
    vki: InstanceProxy,
    vkd: DeviceProxy,
    pdev: vk.PhysicalDevice,
    surface: vk.SurfaceKHR,
    window: *c.SDL_Window,
    indices: QueueFamilyIndices,
    allocator: std.mem.Allocator,
) !struct { swapchain: vk.SwapchainKHR, format: vk.Format, extent: vk.Extent2D, images: []vk.Image } {

    // 1. Get Support Details and pick optimal settings
    const support = try querySwapChainSupport(vki, pdev, surface, allocator);
    defer allocator.free(support.formats);
    defer allocator.free(support.present_modes);

    const surface_format = chooseSwapSurfaceFormat(support.formats);
    const present_mode = chooseSwapPresentMode(support.present_modes);
    const extent = chooseSwapExtent(support.capabilities, window);

    // 2. Choose Image Count (at least one more than the minimum)
    var image_count = support.capabilities.min_image_count + 1;
    if (support.capabilities.max_image_count > 0 and image_count > support.capabilities.max_image_count) {
        image_count = support.capabilities.max_image_count;
    }

    // 3. Define Image Sharing Mode (Concurrent or Exclusive)
    var sharing_mode: vk.SharingMode = undefined;
    var queue_family_indices: [2]u32 = undefined;
    var queue_family_index_count: u32 = 0;

    if (indices.graphics_family.? != indices.present_family.?) {
        // Different queues for Graphics and Present: Use Concurrent mode
        sharing_mode = vk.SharingMode.concurrent;
        queue_family_indices[0] = indices.graphics_family.?;
        queue_family_indices[1] = indices.present_family.?;
        queue_family_index_count = 2;
    } else {
        // Same queue for both: Use Exclusive mode (simpler, usually faster)
        sharing_mode = vk.SharingMode.exclusive;
        queue_family_index_count = 0;
    }

    // 4. Create Info Structure
    const create_info = vk.SwapchainCreateInfoKHR{
        .surface = surface,
        .min_image_count = image_count,
        .image_format = surface_format.format,
        .image_color_space = surface_format.color_space,
        .image_extent = extent,
        .image_array_layers = 1,
        .image_usage = vk.ImageUsageFlags{ .color_attachment_bit = true }, // We render to it
        .image_sharing_mode = sharing_mode,
        .queue_family_index_count = queue_family_index_count,
        .p_queue_family_indices = if (queue_family_index_count > 0) &queue_family_indices else null,
        .pre_transform = support.capabilities.current_transform,
        .composite_alpha = vk.CompositeAlphaFlagsKHR{ .opaque_bit_khr = true },
        .present_mode = present_mode,
        .clipped = vk.TRUE,
        .old_swapchain = .null_handle, // Not recreating yet
    };

    var swapchain: vk.SwapchainKHR = .null_handle;
    const result = vkd.createSwapchainKHR(vkd.handle, &create_info, null, &swapchain);
    if (result != .success) return error.SwapchainCreationFailed;

    // 5. Get the handles to the created images
    var swapchain_image_count: u32 = 0;
    _ = vkd.getSwapchainImagesKHR(vkd.handle, swapchain, &swapchain_image_count, null);
    const images = try allocator.alloc(vk.Image, swapchain_image_count);
    _ = vkd.getSwapchainImagesKHR(vkd.handle, swapchain, &swapchain_image_count, images.ptr);

    return .{
        .swapchain = swapchain,
        .format = surface_format.format,
        .extent = extent,
        .images = images,
    };
}

fn createImageViews(
    vkd: DeviceProxy,
    images: []const vk.Image,
    format: vk.Format,
    allocator: std.mem.Allocator,
) ![]vk.ImageView {
    const image_views = try allocator.alloc(vk.ImageView, images.len);

    for (images, 0..) |image, i| {
        const create_info = vk.ImageViewCreateInfo{
            .image = image,
            .view_type = vk.ImageViewType._2d,
            .format = format,
            .components = vk.ComponentMapping{
                .r = vk.ComponentSwizzle.identity,
                .g = vk.ComponentSwizzle.identity,
                .b = vk.ComponentSwizzle.identity,
                .a = vk.ComponentSwizzle.identity,
            },
            .subresource_range = vk.ImageSubresourceRange{
                .aspect_mask = vk.ImageAspectFlags{ .color_bit = true },
                .base_mip_level = 0,
                .level_count = 1,
                .base_array_layer = 0,
                .layer_count = 1,
            },
        };

        var image_view: vk.ImageView = .null_handle;
        if (vkd.createImageView(vkd.handle, &create_info, null, &image_view) != .success) {
            return error.ImageViewCreationFailed;
        }
        image_views[i] = image_view;
    }

    return image_views;
}

fn createRenderPass(vkd: DeviceProxy, format: vk.Format) !vk.RenderPass {
    // 1. Attachment Description (The color buffer we are rendering to)
    const color_attachment = vk.AttachmentDescription{
        .format = format,
        .samples = vk.SampleCountFlags{ ._1_bit = true },
        .load_op = vk.AttachmentLoadOp.clear, // Clear the screen at start
        .store_op = vk.AttachmentStoreOp.store, // Store the result for presentation
        .stencil_load_op = vk.AttachmentLoadOp.dont_care,
        .stencil_store_op = vk.AttachmentStoreOp.dont_care,
        .initial_layout = vk.ImageLayout.undefined, // Layout at start (we don't care)
        .final_layout = vk.ImageLayout.present_src_khr, // Layout at end (ready for presentation)
    };

    // 2. Attachment Reference (Used by the Subpass)
    const color_attachment_ref = vk.AttachmentReference{
        .attachment = 0, // Index 0 in the attachment array
        .layout = vk.ImageLayout.color_attachment_optimal, // Layout during the subpass
    };

    // 3. Subpass (The main rendering operation)
    const subpass = vk.SubpassDescription{
        .pipeline_bind_point = vk.PipelineBindPoint.graphics,
        .color_attachment_count = 1,
        .p_color_attachments = &color_attachment_ref,
    };

    // 4. Subpass Dependency (Ensures the render pass waits for the swapchain image to be ready)
    const dependency = vk.SubpassDependency{
        .src_subpass = vk.subpassExternal,
        .dst_subpass = 0,
        .src_stage_mask = vk.PipelineStageFlags{ .color_attachment_output_bit = true },
        .src_access_mask = .{},
        .dst_stage_mask = vk.PipelineStageFlags{ .color_attachment_output_bit = true },
        .dst_access_mask = vk.AccessFlags{ .color_attachment_write_bit = true },
    };

    // 5. Create the Render Pass
    const attachments = [_]vk.AttachmentDescription{color_attachment};
    const subpasses = [_]vk.SubpassDescription{subpass};
    const dependencies = [_]vk.SubpassDependency{dependency};

    const render_pass_info = vk.RenderPassCreateInfo{
        .attachment_count = attachments.len,
        .p_attachments = &attachments,
        .subpass_count = subpasses.len,
        .p_subpasses = &subpasses,
        .dependency_count = dependencies.len,
        .p_dependencies = &dependencies,
    };

    var render_pass: vk.RenderPass = .null_handle;
    if (vkd.createRenderPass(vkd.handle, &render_pass_info, null, &render_pass) != .success) {
        return error.RenderPassCreationFailed;
    }
    return render_pass;
}
