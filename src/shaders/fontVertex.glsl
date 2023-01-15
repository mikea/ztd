#version 330 core
layout (location = 0) in vec4 vertex; // <vec2 position, vec2 texCoords>

out vec2 texCoords;

uniform mat4 model;
uniform mat4 projection;
uniform vec4 texRect; // <minx, miny, maxx, maxy> in texture coordinates

void main()
{
    vec2 texOffset = texRect.xy;
    vec2 texScale = texRect.zw - texRect.xy;
    texCoords = texScale * vertex.zw + texOffset;
    gl_Position = projection * model * vec4(vertex.xy, 0.0, 1.0);
}