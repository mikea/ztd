#version 330 core

in vec2 texCoords;
out vec4 color;

uniform float h;

void main() {    
    if (texCoords.x > h) {
        discard;
    } else {
        color = vec4(1, 0, 0, 1);
    }
}  