module git_describe_version;

import std.stdio : writefln;

import version_info : getGitDescribeVersion;

void main()
{
    writefln("Git describe version: %s", getGitDescribeVersion());
}