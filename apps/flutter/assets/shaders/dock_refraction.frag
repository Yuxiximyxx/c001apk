#version 320 es
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform sampler2D uTexture;
uniform vec2 uSize;
uniform float uStrength;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  vec2 centered = uv - vec2(0.5);
  // 椭圆归一化距离：中心≈0、越靠边缘→1，位移随边缘因子增大（中心近乎不动）。
  float dist = length(centered * vec2(1.35, 2.2));
  float edge = smoothstep(0.25, 0.85, dist);
  vec2 offset = -centered * edge * uStrength;
  fragColor = texture(uTexture, clamp(uv + offset, vec2(0.001), vec2(0.999)));
}
