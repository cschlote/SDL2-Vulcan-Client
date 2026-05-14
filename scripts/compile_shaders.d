#!/usr/bin/env rdmd
/** Compiles the repository's GLSL shaders into SPIR-V binaries.
 *
 * Checks source and output timestamps, creates the shader output directory,
 * and rebuilds the shader artifacts when the inputs changed. The shader roles
 * are documented in docs/shaders.md.
 *
 * See_Also:
 *   docs/shaders.md
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
 * License: CC-BY-NC-SA 4.0
 */
module scripts.compile_shaders;

import std.file : exists, mkdirRecurse, timeLastModified;
import std.process : executeShell;
import std.stdio : writefln;

private struct ShaderPair
{
    string source;
    string output;
}

/** Compiles the repository's GLSL shaders into SPIR-V binaries. */
void main()
{
    const ShaderPair[] shaders = [
        ShaderPair("shaders/main.vert", "build/shaders/main.vert.spv"),
        ShaderPair("shaders/main.frag", "build/shaders/main.frag.spv"),
    ];

    mkdirRecurse("build/shaders");

    foreach (shader; shaders)
    {
        if (!needsCompile(shader.source, shader.output))
        {
            writefln("Up to date: %s -> %s", shader.source, shader.output);
            continue;
        }

        const command = "glslangValidator -V " ~ shader.source ~ " -o " ~ shader.output;
        const result = executeShell(command);
        if (result.status != 0)
            throw new Exception("Shader compilation failed: " ~ shader.source);

        writefln("Compiled: %s -> %s", shader.source, shader.output);
    }
}

/** Returns whether a shader source file is newer than its compiled output.
 *
 * Params:
 *   sourcePath = Path to the GLSL source file.
 *   outputPath = Path to the generated SPIR-V file.
 * Returns: `true` when the shader should be rebuilt, otherwise `false`.
 */
private bool needsCompile(string sourcePath, string outputPath)
{
    if (!exists(outputPath))
        return true;

    return timeLastModified(sourcePath) > timeLastModified(outputPath);
}