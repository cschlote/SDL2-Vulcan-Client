#!/usr/bin/env rdmd
/** Writes the current Git describe string to a build artifact.
 *
 * Runs `git describe`, stores the result in `build/git-describe.txt`, and
 * prints the generated value for release and version diagnostics.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
 * License: CC-BY-NC-SA 4.0
 */
module scripts.git_describe_version;

import std.file : mkdirRecurse, write;
import std.process : executeShell;
import std.stdio : writefln;
import std.string : strip;

private enum outputPath = "build/git-describe.txt";

/** Writes the current `git describe` value to the generated build artifact. */
void main()
{
    const result = executeShell("git describe --tag --always --long");
    auto describeVersion = result.output.strip;
    if (result.status != 0 || describeVersion.length == 0)
        describeVersion = "unknown";

    mkdirRecurse("build");
    write(outputPath, describeVersion ~ "\n");
    writefln("Wrote %s: %s", outputPath, describeVersion);
}