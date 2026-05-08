/** Application bootstrap that loads SDL and Vulkan, creates the window, and drives the renderer. */
module app;

import bindbc.loader : LoadMsg;
import bindbc.sdl : SDL_GetError, SDL_Init, SDL_InitFlags, SDL_Quit, loadSDL;
import bindbc.vulkan : VulkanSupport, loadVulkan;
import std.stdio : stderr;
import std.string : fromStringz;

import window;
import vulkan.renderer : VulkanRenderer;
import version_info : getGitDescribeVersion;

/** Loads the SDL shared library bindings and reports failures on standard error.
 *
 * @returns `true` when the bindings were loaded successfully, otherwise `false`.
 */
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

/** Loads the Vulkan shared library bindings and reports failures on standard error.
 *
 * @returns `true` when the bindings were loaded successfully, otherwise `false`.
 */
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

/** Runs the SDL/Vulkan demo application and returns a process exit code.
 *
 * @param args = Command-line arguments passed to the executable.
 * @returns `0` on success or `1` if initialization or runtime setup fails.
 */
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
