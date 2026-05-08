/** Program entry point that forwards to the application runner. */
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
