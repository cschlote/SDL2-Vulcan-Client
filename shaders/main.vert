/* Vertex shader for the demo scene and overlay-style geometry.
 *
 * It forwards position, color, normal, and UV attributes to the fragment
 * stage and writes clip-space position directly from the incoming vertex.
 */
#version 450

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec4 inColor;
layout(location = 2) in vec3 inNormal;
layout(location = 3) in vec2 inUv;

layout(location = 0) out vec4 fragColor;
layout(location = 1) out vec3 fragNormal;
layout(location = 2) out vec2 fragUv;

void main()
{
    fragColor = inColor;
    fragNormal = inNormal;
    fragUv = inUv;
    gl_Position = vec4(inPosition, 1.0);
}
