#version 330 core
layout (location = 0) in vec4 vertex; // <vec2 position, vec2 texCoords>

out vec2 texCoords;

uniform mat4 model;
uniform mat4 projection;

uniform vec2 texScale;
uniform vec2 texOffset;

void main()
{
    texCoords = texScale * vertex.zw + texOffset;
    gl_Position = projection * model * vec4(vertex.xy, 0.0, 1.0);
}