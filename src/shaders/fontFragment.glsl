#version 330 core

in vec2 texCoords;
out vec4 color;

uniform sampler2D image;
uniform vec4 textColor;

void main() {        
    color = texture(image, texCoords);
    color = textColor * vec4(1, 1, 1, color.r);
}  