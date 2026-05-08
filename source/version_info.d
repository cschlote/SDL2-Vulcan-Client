/** Small helper that embeds the Git describe version generated at build time. */
module version_info;

import std.string : strip;

enum gitDescribeVersion = import("build/git-describe.txt").strip;

/** Returns the cached Git describe version string from the generated build artifact.
 *
 * @returns The trimmed Git describe version string.
 */
string getGitDescribeVersion()
{
    return gitDescribeVersion.idup;
}