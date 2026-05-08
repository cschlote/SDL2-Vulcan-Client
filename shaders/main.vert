#version 450

layout(location = 0) out vec3 fragColor;

void main()
{
    const vec2 positions[3] = vec2[](
        vec2(-0.92, -0.86),
        vec2(0.00, 0.94),
        vec2(0.92, -0.86)
    );

    const vec3 colors[3] = vec3[](
        vec3(1.0, 0.1, 0.1),
        vec3(0.1, 1.0, 0.2),
        vec3(0.1, 0.4, 1.0)
    );

    fragColor = colors[gl_VertexIndex];
    gl_Position = vec4(positions[gl_VertexIndex], 0.0, 1.0);
}
