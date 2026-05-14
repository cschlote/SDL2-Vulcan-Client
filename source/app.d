/** Bootstraps SDL, Vulkan, and the renderer.
 *
 * Loads the native bindings, initializes the SDL video subsystem, creates the
 * window wrapper, constructs the Vulkan renderer, and performs shutdown in the
 * correct order. The bootstrap flow mirrors the step-by-step frame lifecycle
 * described in docs/vulkan-quickstart.md.
 *
 * See_Also:
 *   docs/vulkan-quickstart.md
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module app;

import bindbc.loader : LoadMsg;
import bindbc.sdl : SDL_GetError, SDL_Init, SDL_InitFlags, SDL_Quit, loadSDL;
import bindbc.vulkan : VulkanSupport, loadVulkan;
import std.stdio : stderr;
import std.string : fromStringz;

import logging : logLine, logLineVerbose, setVerboseOutputs;
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
    bool verbose = false;
    foreach (arg; args[1 .. $])
    {
        if (arg == "-v" || arg == "--verbose")
            verbose = true;
    }

    setVerboseOutputs(verbose);
    logLine("Starting SDL2 Vulkan demo.");
    logLineVerbose("Verbose logging enabled.");
    logLineVerbose("Arguments: ", args);

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
        logLine("Build version: ", buildVersion);
        logLineVerbose("SDL and Vulkan bindings loaded successfully.");

        auto window = SdlWindow("SDL2 Vulkan Demo " ~ buildVersion, 1280, 720);
        scope (exit)
            window.destroy();

        auto renderer = new VulkanRenderer(&window, buildVersion);
        scope (exit)
            renderer.destroy();

        logLineVerbose("Entering renderer loop.");
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
