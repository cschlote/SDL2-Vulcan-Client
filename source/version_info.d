/** $purposeofFile
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
 * License: CC-BY-NC-SA 4.0
 */
module version_info;

import std.string : strip;

private enum gitDescribeVersion = import("build/git-describe.txt").strip;

/** Returns the cached Git describe version string from the generated build artifact.
 *
 * @returns The trimmed Git describe version string.
 */
string getGitDescribeVersion()
{
    return gitDescribeVersion.idup;
}