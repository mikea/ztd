#version 330 core

in vec2 texCoords;
out vec4 color;

uniform sampler2D image;

void main() {    
    color = texture(image, texCoords);
    if (color.a < .1) {
        discard;
    }
    // color = vec4(0, 0, 0, 1);
}  