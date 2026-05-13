/* Fragment shader for the main scene.
 *
 * Mode 0 renders flat color, mode 1 applies lighting and a tiled diffuse
 * texture, and mode 2 multiplies the vertex color by the sampled texture.
 */
#version 450

layout(location = 0) in vec4 fragColor;
layout(location = 1) in vec3 fragNormal;
layout(location = 2) in vec2 fragUv;

layout(set = 0, binding = 0) uniform SceneUniforms
{
    vec4 lightDirectionMode;
    vec4 shadingParams;
} scene;

layout(set = 0, binding = 1) uniform sampler2D diffuseTexture;

layout(location = 0) out vec4 outColor;

void main()
{
    float modeValue = scene.lightDirectionMode.w;
    if (modeValue < 0.0)
    {
        if (modeValue < -1.5)
        {
            vec4 textureColor = texture(diffuseTexture, fragUv);
            outColor = vec4(fragColor.rgb * textureColor.rgb, fragColor.a * textureColor.a);
        }
        else
        {
            outColor = fragColor;
        }

        return;
    }

    int mode = int(modeValue + 0.5);
    if (mode == 0)
    {
        outColor = fragColor;
        return;
    }

    if (mode == 2)
    {
        vec4 textureColor = texture(diffuseTexture, fragUv);
        outColor = fragColor * textureColor;
        return;
    }

    vec4 textureColor = texture(diffuseTexture, fragUv * 6.0);

    vec3 normal = normalize(fragNormal);
    vec3 lightDirection = normalize(scene.lightDirectionMode.xyz);
    float diffuse = max(dot(normal, lightDirection), 0.0);
    vec3 viewDirection = vec3(0.0, 0.0, 1.0);
    vec3 halfVector = normalize(lightDirection + viewDirection);
    float specular = pow(max(dot(normal, halfVector), 0.0), scene.shadingParams.w) * scene.shadingParams.z;

    vec4 litColor = fragColor * textureColor;
    litColor.rgb *= scene.shadingParams.x + diffuse * scene.shadingParams.y;
    litColor.rgb += specular;
    litColor.a = fragColor.a * textureColor.a;

    outColor = litColor;
}
