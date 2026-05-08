module scripts.compile_shaders;

import std.file : exists, mkdirRecurse, timeLastModified;
import std.process : executeShell;
import std.stdio : writefln;

private struct ShaderPair
{
    string source;
    string output;
}

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

private bool needsCompile(string sourcePath, string outputPath)
{
    if (!exists(outputPath))
        return true;

    return timeLastModified(sourcePath) > timeLastModified(outputPath);
}