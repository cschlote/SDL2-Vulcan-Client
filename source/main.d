/** $purposeofFile
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
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
