module app;

import bindbc.loader : LoadMsg;
import bindbc.sdl : SDL_GetError, SDL_Init, SDL_InitFlags, SDL_Quit, loadSDL;
import bindbc.vulkan : VulkanSupport, loadVulkan;
import std.stdio : stderr;
import std.string : fromStringz;

import window;
import vulkan.renderer : VulkanRenderer;
import version_info : getGitDescribeVersion;

private bool loadSdlBindings()
{
    const result = loadSDL();
    if (result != LoadMsg.success)
    {
        stderr.writeln("Failed to load SDL bindings.");
        return false;
    }

    return true;
}

private bool loadVulkanBindings()
{
    const result = loadVulkan();
    if (result != VulkanSupport.v103)
    {
        stderr.writeln("Failed to load Vulkan bindings.");
        return false;
    }

    return true;
}

int runApplication(string[] args)
{
    if (!loadSdlBindings())
        return 1;

    if (!loadVulkanBindings())
        return 1;

    if (!SDL_Init(SDL_InitFlags.video))
    {
        stderr.writeln("SDL_Init failed: ", fromStringz(SDL_GetError()));
        return 1;
    }

    int exitCode = 0;
    try
    {
        const buildVersion = getGitDescribeVersion();
        stderr.writeln("Build version: ", buildVersion);

        auto window = SdlWindow("SDL2 Vulkan Demo " ~ buildVersion, 1280, 720);
        scope (exit)
            window.destroy();

        auto renderer = new VulkanRenderer(&window, buildVersion);
        scope (exit)
            renderer.destroy();

        renderer.run();
    }
    catch (Exception exception)
    {
        stderr.writeln(exception.msg);
        exitCode = 1;
    }
    finally
    {
        SDL_Quit();
    }

    return exitCode;
}
