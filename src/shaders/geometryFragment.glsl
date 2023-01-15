#version 330 core

in vec2 texCoords;
out vec4 color;

uniform vec4 geomColor;

void main() {    
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(center, texCoords);

    // only circles are supported atm
    if (dist > 0.5) {
        discard;
    } else {
        color = geomColor;
    }
}  