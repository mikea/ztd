#version 330 core

in vec2 texCoords;
out vec4 color;

uniform vec4 geomColor;

// 0 - disk
// 1 - rect
uniform int geomType;

void main() {    
    if (geomType == 0) {
        vec2 center = vec2(0.5, 0.5);
        float dist = distance(center, texCoords);
        if (dist > 0.5) {
            discard;
        } else {
            color = geomColor;
        }
    } else {
        color = geomColor;
    }
}  