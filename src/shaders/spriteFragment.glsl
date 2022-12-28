#version 330 core

in vec2 texCoords;
out vec4 color;

uniform sampler2D image;

void main() {    
    color = texture(image, texCoords);
    // color = vec4(0, 0, 0, 1);
}  