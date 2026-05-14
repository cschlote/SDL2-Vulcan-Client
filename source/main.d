/** Runs the application entry point for the demo.
 *
 * Forwards the command-line arguments to the bootstrap layer and returns the
 * process exit code from the renderer workflow. See the repository README and
 * docs/vulkan-quickstart.md for the higher-level project entry points.
 *
 * See_Also:
 *   README.md
 *   docs/vulkan-quickstart.md
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018-2026
 * License: CC-BY-NC-SA 4.0
 */
module main;

import app;

/** Starts the application by forwarding the command-line arguments to the app module.
 *
 * @param args = Command-line arguments passed by the runtime.
 * @returns The process exit code from the application runner.
 */
int main(string[] args)
{
    return runApplication(args);
}
