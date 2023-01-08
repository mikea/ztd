#version 330 core
layout (location = 0) in vec4 vertex; // <vec2 position, vec2 texCoords>
layout (location = 1) in vec4 rect; // <minx, miny, maxx, maxy> in game coordinates
layout (location = 2) in vec2 angleLayer; // <angle radians, layer>

out vec2 texCoords;

uniform mat4 projection;

// uniform vec2 texScale;
// uniform vec2 texOffset;

void main()
{
    float z = angleLayer.y;
    float co = cos(angleLayer.x);
    float si = sin(angleLayer.x);

    float l = rect.x;
    float b = rect.y;
    float w = rect.z - l;
    float h = rect.w - b;

    mat4 model = mat4(
        vec4(w * co,                          w * si,                          0, 0),
        vec4(-h * si,                         h * co,                          0, 0),
        vec4(0,                               0,                               1, 0),
        vec4(l + 0.5 * (w - w * co + h * si), b + 0.5 * (h - h * co - w * si), z, 1)
    );
    // texCoords = texScale * vertex.zw + texOffset;
    texCoords = vertex.zw;
    gl_Position = projection * model * vec4(vertex.xy, 0.0, 1.0);
}