module vulkan.polyhedra;

import std.algorithm : sort;
import std.math : abs, atan2, sqrt;

import vulkan.pipeline : Vertex;

struct MeshData
{
    string name;
    Vertex[] vertices;
    uint[] indices;
}

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

private MeshData buildConvexSolid(string name, const(float[3])[] positions)
{
    auto faces = extractFaces(positions);

    Vertex[] vertices;
    uint[] indices;

    foreach (faceIndex, face; faces)
    {
        const color = paletteColor(faceIndex);
        const baseVertex = cast(uint)vertices.length;

        foreach (vertexIndex; face.vertexIndices)
            vertices ~= Vertex(positions[vertexIndex], color);

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

private struct FacePolygon
{
    uint[] vertexIndices;
    float[3] normal;
    float distance;
}

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

private float dot(float[3] left, float[3] right)
{
    return left[0] * right[0] + left[1] * right[1] + left[2] * right[2];
}

private float[3] add(float[3] left, float[3] right)
{
    return [left[0] + right[0], left[1] + right[1], left[2] + right[2]];
}

private float[3] subtract(float[3] left, float[3] right)
{
    return [left[0] - right[0], left[1] - right[1], left[2] - right[2]];
}

private float[3] scale(float[3] value, float factor)
{
    return [value[0] * factor, value[1] * factor, value[2] * factor];
}

private float[3] negate(float[3] value)
{
    return [-value[0], -value[1], -value[2]];
}

private float[3] cross(float[3] left, float[3] right)
{
    return [
        left[1] * right[2] - left[2] * right[1],
        left[2] * right[0] - left[0] * right[2],
        left[0] * right[1] - left[1] * right[0],
    ];
}

private float length(float[3] value)
{
    return sqrt(dot(value, value));
}

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