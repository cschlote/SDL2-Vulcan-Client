module version_info;

import std.process : executeShell;
import std.string : strip;

string getGitDescribeVersion()
{
    const result = executeShell("git describe --tag --always --long");
    auto describeVersion = result.output.strip;
    if (result.status != 0 || describeVersion.length == 0)
        return "unknown";

    return describeVersion.idup;
}