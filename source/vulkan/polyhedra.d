/** Builds indexed meshes for the selectable Platonic solids.
 *
 * Reconstructs convex faces from the vertex sets, assigns per-face colors, and
 * emits triangulated mesh data that the renderer can upload directly.
 *
 * Authors: Carsten Schlote, schlote@vahanus.net
 * Copyright: Carsten Schlote, Released under CC-BY-NC-SA 4.0 license, 2018
 * License: CC-BY-NC-SA 4.0
 */
module vulkan.polyhedra;

import std.algorithm : sort;
import std.math : abs, atan2, sqrt;

import vulkan.pipeline : Vertex;

/** Describes a mesh that can be uploaded to the renderer. */
struct MeshData
{
    string name;
    Vertex[] vertices;
    uint[] indices;
}

/** Builds the set of selectable Platonic solids.
 *
 * @returns Mesh data for the tetrahedron, cube, octahedron, dodecahedron, and icosahedron.
 */
MeshData[] buildPlatonicSolids()
{
    return [
        buildConvexSolid("TETRAHEDRON", tetrahedronVertices),
        buildConvexSolid("CUBE", cubeVertices),
        buildConvexSolid("OCTAHEDRON", octahedronVertices),
        buildConvexSolid("DODECAHEDRON", dodecahedronVertices),
        buildConvexSolid("ICOSAHEDRON", icosahedronVertices),
    ];
}

/** Builds a convex solid mesh from a list of vertex positions.
 *
 * @param name = Human-readable mesh name.
 * @param positions = Vertex positions of the solid.
 * @returns Mesh data containing colored vertices and triangle indices.
 */
private MeshData buildConvexSolid(string name, const(float[3])[] positions)
{
    auto faces = extractFaces(positions);

    Vertex[] vertices;
    uint[] indices;

    foreach (faceIndex, face; faces)
    {
        const color = paletteColor(faceIndex);
        const baseVertex = cast(uint)vertices.length;
        float[3] center = [0.0f, 0.0f, 0.0f];
        foreach (vertexIndex; face.vertexIndices)
            center = add(center, positions[vertexIndex]);
        center = scale(center, 1.0f / cast(float)face.vertexIndices.length);

        float[3] helper;
        if (abs(face.normal[1]) < 0.9f)
            helper = [0.0f, 1.0f, 0.0f];
        else
            helper = [1.0f, 0.0f, 0.0f];

        auto axisX = normalize(cross(helper, face.normal));
        auto axisY = cross(face.normal, axisX);

        float[2][] rawUvs;
        rawUvs.length = face.vertexIndices.length;
        foreach (index, vertexIndex; face.vertexIndices)
        {
            const relative = subtract(positions[vertexIndex], center);
            rawUvs[index] = [dot(relative, axisX), dot(relative, axisY)];
        }

        float minU = rawUvs[0][0];
        float maxU = rawUvs[0][0];
        float minV = rawUvs[0][1];
        float maxV = rawUvs[0][1];
        foreach (rawUv; rawUvs)
        {
            if (rawUv[0] < minU)
                minU = rawUv[0];
            if (rawUv[0] > maxU)
                maxU = rawUv[0];
            if (rawUv[1] < minV)
                minV = rawUv[1];
            if (rawUv[1] > maxV)
                maxV = rawUv[1];
        }

        const uRange = maxU - minU > 1e-5f ? maxU - minU : 1.0f;
        const vRange = maxV - minV > 1e-5f ? maxV - minV : 1.0f;

        foreach (index, vertexIndex; face.vertexIndices)
        {
            const rawUv = rawUvs[index];
            float[2] uv = [(rawUv[0] - minU) / uRange, (rawUv[1] - minV) / vRange];
            vertices ~= Vertex(positions[vertexIndex], color, face.normal, uv);
        }

        const cornerCount = cast(uint)face.vertexIndices.length;
        foreach (triangleIndex; 1 .. cornerCount - 1)
        {
            indices ~= baseVertex;
            indices ~= baseVertex + cast(uint)triangleIndex;
            indices ~= baseVertex + cast(uint)triangleIndex + 1;
        }
    }

    return MeshData(name, vertices, indices);
}

/** Stores a polygonal face discovered while reconstructing a convex solid. */
private struct FacePolygon
{
    uint[] vertexIndices;
    float[3] normal;
    float distance;
}

/** Extracts the planar faces that make up a convex solid.
 *
 * @param positions = Vertex positions of the solid.
 * @returns A list of polygon faces with consistent winding.
 */
private FacePolygon[] extractFaces(const(float[3])[] positions)
{
    FacePolygon[] faces;
    enum epsilon = 1e-3f;

    foreach (i; 0 .. positions.length)
    {
        foreach (j; i + 1 .. positions.length)
        {
            foreach (k; j + 1 .. positions.length)
            {
                auto a = positions[i];
                auto b = positions[j];
                auto c = positions[k];
                auto normal = normalize(cross(subtract(b, a), subtract(c, a)));
                if (length(normal) <= epsilon)
                    continue;

                const distance = dot(normal, a);
                bool hasPositive = false;
                bool hasNegative = false;

                foreach (index, point; positions)
                {
                    if (index == i || index == j || index == k)
                        continue;

                    const side = dot(normal, point) - distance;
                    if (side > epsilon)
                        hasPositive = true;
                    else if (side < -epsilon)
                        hasNegative = true;

                    if (hasPositive && hasNegative)
                        break;
                }

                if (hasPositive && hasNegative)
                    continue;

                auto faceNormal = normal;
                float faceDistance = distance;
                if (hasPositive)
                {
                    faceNormal = negate(faceNormal);
                    faceDistance = -faceDistance;
                }

                if (faceDistance < 0)
                    continue;

                if (containsFace(faces, faceNormal, faceDistance))
                    continue;

                uint[] faceVertices;
                foreach (index, point; positions)
                {
                    if (abs(dot(faceNormal, point) - faceDistance) <= epsilon)
                        faceVertices ~= cast(uint)index;
                }

                if (faceVertices.length < 3)
                    continue;

                sortFaceVertices(faceVertices, faceNormal, positions);
                faces ~= FacePolygon(faceVertices, faceNormal, faceDistance);
            }
        }
    }

    return faces;
}

/** Checks whether an equivalent face has already been recorded.
 *
 * @param faces = Faces already discovered.
 * @param normal = Candidate face normal.
 * @param distance = Candidate plane distance.
 * @returns `true` when the face is already present, otherwise `false`.
 */
private bool containsFace(const(FacePolygon)[] faces, float[3] normal, float distance)
{
    enum epsilon = 1e-3f;

    foreach (face; faces)
    {
        if (dot(face.normal, normal) > 1.0f - epsilon && abs(face.distance - distance) <= epsilon)
            return true;
    }

    return false;
}

/** Sorts face vertices around the face center for consistent triangle fan generation.
 *
 * @param faceVertices = Vertex indices to sort in place.
 * @param normal = Face normal.
 * @param positions = Source vertex positions.
 * @returns Nothing.
 */
private void sortFaceVertices(ref uint[] faceVertices, float[3] normal, const(float[3])[] positions)
{
    float[3] center = [0.0f, 0.0f, 0.0f];
    foreach (vertexIndex; faceVertices)
        center = add(center, positions[vertexIndex]);
    center = scale(center, 1.0f / cast(float)faceVertices.length);

    float[3] helper;
    if (abs(normal[1]) < 0.9f)
        helper = [0.0f, 1.0f, 0.0f];
    else
        helper = [1.0f, 0.0f, 0.0f];
    auto axisX = normalize(cross(helper, normal));
    auto axisY = cross(normal, axisX);

    struct VertexAngle
    {
        uint index;
        float angle;
    }

    VertexAngle[] ordered;
    foreach (vertexIndex; faceVertices)
    {
        const relative = subtract(positions[vertexIndex], center);
        const x = dot(relative, axisX);
        const y = dot(relative, axisY);
        ordered ~= VertexAngle(vertexIndex, atan2(y, x));
    }

    ordered.sort!((left, right) => left.angle < right.angle);

    faceVertices.length = 0;
    foreach (entry; ordered)
        faceVertices ~= entry.index;
}

/** Returns a palette color for a face index.
 *
 * @param index = Zero-based face index.
 * @returns RGBA color used for the face.
 */
private float[4] paletteColor(size_t index)
{
    static immutable float[4][] palette = [
        [0.95f, 0.28f, 0.30f, 1.0f],
        [0.95f, 0.56f, 0.22f, 1.0f],
        [0.93f, 0.80f, 0.24f, 1.0f],
        [0.56f, 0.84f, 0.30f, 1.0f],
        [0.28f, 0.82f, 0.62f, 1.0f],
        [0.30f, 0.66f, 0.95f, 1.0f],
        [0.46f, 0.42f, 0.95f, 1.0f],
        [0.82f, 0.32f, 0.92f, 1.0f],
        [0.92f, 0.35f, 0.64f, 1.0f],
        [0.78f, 0.78f, 0.82f, 1.0f],
        [0.58f, 0.40f, 0.24f, 1.0f],
        [0.22f, 0.88f, 0.90f, 1.0f],
    ];

    return palette[index % palette.length];
}

/** Computes the dot product of two 3D vectors.
 *
 * @param left = Left-hand vector.
 * @param right = Right-hand vector.
 * @returns Scalar dot product.
 */
private float dot(float[3] left, float[3] right)
{
    return left[0] * right[0] + left[1] * right[1] + left[2] * right[2];
}

/** Adds two 3D vectors.
 *
 * @param left = Left-hand vector.
 * @param right = Right-hand vector.
 * @returns Component-wise sum.
 */
private float[3] add(float[3] left, float[3] right)
{
    return [left[0] + right[0], left[1] + right[1], left[2] + right[2]];
}

/** Subtracts two 3D vectors.
 *
 * @param left = Left-hand vector.
 * @param right = Right-hand vector.
 * @returns Component-wise difference.
 */
private float[3] subtract(float[3] left, float[3] right)
{
    return [left[0] - right[0], left[1] - right[1], left[2] - right[2]];
}

/** Multiplies a 3D vector by a scalar.
 *
 * @param value = Input vector.
 * @param factor = Scalar multiplier.
 * @returns Scaled vector.
 */
private float[3] scale(float[3] value, float factor)
{
    return [value[0] * factor, value[1] * factor, value[2] * factor];
}

/** Negates a 3D vector.
 *
 * @param value = Input vector.
 * @returns Negated vector.
 */
private float[3] negate(float[3] value)
{
    return [-value[0], -value[1], -value[2]];
}

/** Computes the cross product of two 3D vectors.
 *
 * @param left = Left-hand vector.
 * @param right = Right-hand vector.
 * @returns Orthogonal vector.
 */
private float[3] cross(float[3] left, float[3] right)
{
    return [
        left[1] * right[2] - left[2] * right[1],
        left[2] * right[0] - left[0] * right[2],
        left[0] * right[1] - left[1] * right[0],
    ];
}

/** Computes the length of a 3D vector.
 *
 * @param value = Input vector.
 * @returns Vector magnitude.
 */
private float length(float[3] value)
{
    return sqrt(dot(value, value));
}

/** Normalizes a 3D vector.
 *
 * @param value = Input vector.
 * @returns Unit-length vector.
 */
private float[3] normalize(float[3] value)
{
    const magnitude = length(value);
    if (magnitude <= 0.0f)
        return [0.0f, 0.0f, 0.0f];

    return [value[0] / magnitude, value[1] / magnitude, value[2] / magnitude];
}

private immutable float[3][] tetrahedronVertices = [
    [ 1.0f,  1.0f,  1.0f],
    [-1.0f, -1.0f,  1.0f],
    [-1.0f,  1.0f, -1.0f],
    [ 1.0f, -1.0f, -1.0f],
];

private immutable float[3][] cubeVertices = [
    [-1.0f, -1.0f,  1.0f],
    [ 1.0f, -1.0f,  1.0f],
    [ 1.0f,  1.0f,  1.0f],
    [-1.0f,  1.0f,  1.0f],
    [ 1.0f, -1.0f, -1.0f],
    [-1.0f, -1.0f, -1.0f],
    [-1.0f,  1.0f, -1.0f],
    [ 1.0f,  1.0f, -1.0f],
];

private immutable float[3][] octahedronVertices = [
    [ 1.0f,  0.0f,  0.0f],
    [-1.0f,  0.0f,  0.0f],
    [ 0.0f,  1.0f,  0.0f],
    [ 0.0f, -1.0f,  0.0f],
    [ 0.0f,  0.0f,  1.0f],
    [ 0.0f,  0.0f, -1.0f],
];

private immutable float[3][] icosahedronVertices = [
    [ 0.0f,  1.0f,  1.618_034f],
    [ 0.0f, -1.0f,  1.618_034f],
    [ 0.0f,  1.0f, -1.618_034f],
    [ 0.0f, -1.0f, -1.618_034f],
    [ 1.0f,  1.618_034f,  0.0f],
    [-1.0f,  1.618_034f,  0.0f],
    [ 1.0f, -1.618_034f,  0.0f],
    [-1.0f, -1.618_034f,  0.0f],
    [ 1.618_034f,  0.0f,  1.0f],
    [-1.618_034f,  0.0f,  1.0f],
    [ 1.618_034f,  0.0f, -1.0f],
    [-1.618_034f,  0.0f, -1.0f],
];

private immutable float[3][] dodecahedronVertices = [
    [ 1.0f,  1.0f,  1.0f],
    [ 1.0f,  1.0f, -1.0f],
    [ 1.0f, -1.0f,  1.0f],
    [ 1.0f, -1.0f, -1.0f],
    [-1.0f,  1.0f,  1.0f],
    [-1.0f,  1.0f, -1.0f],
    [-1.0f, -1.0f,  1.0f],
    [-1.0f, -1.0f, -1.0f],
    [ 0.0f,  0.618_034f,  1.618_034f],
    [ 0.0f,  0.618_034f, -1.618_034f],
    [ 0.0f, -0.618_034f,  1.618_034f],
    [ 0.0f, -0.618_034f, -1.618_034f],
    [ 0.618_034f,  1.618_034f,  0.0f],
    [ 0.618_034f, -1.618_034f,  0.0f],
    [-0.618_034f,  1.618_034f,  0.0f],
    [-0.618_034f, -1.618_034f,  0.0f],
    [ 1.618_034f,  0.0f,  0.618_034f],
    [ 1.618_034f,  0.0f, -0.618_034f],
    [-1.618_034f,  0.0f,  0.618_034f],
    [-1.618_034f,  0.0f, -0.618_034f],
];