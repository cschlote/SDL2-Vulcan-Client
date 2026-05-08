module math.matrix;

import std.math : PI, cos, sin, sqrt, tan;

struct Vec3
{
    float x;
    float y;
    float z;
}

struct Mat4
{
    float[16] m;

    static Mat4 identity() pure nothrow @nogc @safe
    {
        Mat4 result;
        result.m[0] = 1;
        result.m[5] = 1;
        result.m[10] = 1;
        result.m[15] = 1;
        return result;
    }
}

pure nothrow @nogc:

float dot(Vec3 a, Vec3 b)
{
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

Vec3 cross(Vec3 a, Vec3 b)
{
    return Vec3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x);
}

float length(Vec3 value)
{
    return sqrt(dot(value, value));
}

Vec3 normalize(Vec3 value)
{
    const invLength = 1.0f / length(value);
    return Vec3(value.x * invLength, value.y * invLength, value.z * invLength);
}

Mat4 multiply(Mat4 left, Mat4 right)
{
    Mat4 result;
    foreach (column; 0 .. 4)
    {
        foreach (row; 0 .. 4)
        {
            float sum = 0;
            foreach (k; 0 .. 4)
            {
                sum += left.m[k * 4 + row] * right.m[column * 4 + k];
            }
            result.m[column * 4 + row] = sum;
        }
    }
    return result;
}

Mat4 translation(Vec3 offset)
{
    auto result = Mat4.identity();
    result.m[12] = offset.x;
    result.m[13] = offset.y;
    result.m[14] = offset.z;
    return result;
}

Mat4 rotationX(float radians)
{
    auto result = Mat4.identity();
    const c = cos(radians);
    const s = sin(radians);
    result.m[5] = c;
    result.m[6] = s;
    result.m[9] = -s;
    result.m[10] = c;
    return result;
}

Mat4 rotationY(float radians)
{
    auto result = Mat4.identity();
    const c = cos(radians);
    const s = sin(radians);
    result.m[0] = c;
    result.m[2] = -s;
    result.m[8] = s;
    result.m[10] = c;
    return result;
}

Mat4 rotationZ(float radians)
{
    auto result = Mat4.identity();
    const c = cos(radians);
    const s = sin(radians);
    result.m[0] = c;
    result.m[1] = s;
    result.m[4] = -s;
    result.m[5] = c;
    return result;
}

Mat4 scale(Vec3 factors)
{
    Mat4 result;
    result.m[0] = factors.x;
    result.m[5] = factors.y;
    result.m[10] = factors.z;
    result.m[15] = 1;
    return result;
}

Mat4 perspective(float fovYRadians, float aspect, float nearPlane, float farPlane)
{
    Mat4 result;
    const f = 1.0f / tan(fovYRadians * 0.5f);
    result.m[0] = f / aspect;
    result.m[5] = -f;
    result.m[10] = farPlane / (nearPlane - farPlane);
    result.m[11] = -1;
    result.m[14] = (farPlane * nearPlane) / (nearPlane - farPlane);
    return result;
}

Mat4 lookAt(Vec3 eye, Vec3 center, Vec3 up)
{
    const forward = normalize(Vec3(center.x - eye.x, center.y - eye.y, center.z - eye.z));
    const side = normalize(cross(forward, up));
    const upVector = cross(side, forward);

    Mat4 result = Mat4.identity();
    result.m[0] = side.x;
    result.m[4] = side.y;
    result.m[8] = side.z;
    result.m[1] = upVector.x;
    result.m[5] = upVector.y;
    result.m[9] = upVector.z;
    result.m[2] = -forward.x;
    result.m[6] = -forward.y;
    result.m[10] = -forward.z;
    result.m[12] = -dot(side, eye);
    result.m[13] = -dot(upVector, eye);
    result.m[14] = dot(forward, eye);
    return result;
}

unittest
{
    const a = translation(Vec3(1, 2, 3));
    const b = scale(Vec3(2, 3, 4));
    const result = multiply(a, b);
    assert(result.m[0] == 2);
    assert(result.m[5] == 3);
    assert(result.m[10] == 4);
    assert(result.m[12] == 1);
    assert(result.m[13] == 2);
    assert(result.m[14] == 3);
}
