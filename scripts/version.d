module git_describe_version;

import std.file : mkdirRecurse, write;
import std.process : executeShell;
import std.stdio : writefln;
import std.string : strip;

private enum outputPath = "build/git-describe.txt";

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