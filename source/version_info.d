module version_info;

import std.string : strip;

enum gitDescribeVersion = import("build/git-describe.txt").strip;

string getGitDescribeVersion()
{
    return gitDescribeVersion.idup;
}