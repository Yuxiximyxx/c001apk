#version 320 es
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform sampler2D uTexture;
uniform vec2 uSize;    // 元素尺寸（物理像素）
uniform float uBand;   // 折射带宽（物理像素，24dp）
uniform float uAmount; // 折射量（物理像素，24dp；剖面峰值取 0.5 倍）
uniform float uChromatic; // 色差开关（1=开，0=关）；miuix15 药丸透镜用

out vec4 fragColor;

// 胶囊（圆角 = 短边一半的 stadium）带符号距离场：内部为负、边缘为 0。
float capsuleSdf(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - (halfSize - vec2(r));
  return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 uv = p / uSize;
  vec2 center = uSize * 0.5;
  vec2 local = p - center;
  float r = min(uSize.x, uSize.y) * 0.5;
  float sd = capsuleSdf(local, center, r);
  float depth = -sd; // 距边缘的距离（内部 ≥ 0）

  // 带外（深处）与元素外不折射。
  if (depth < 0.0 || depth >= uBand) {
    fragColor = texture(uTexture, uv);
    return;
  }

  // SDF 梯度 = 外法线方向（中心差分）。
  float e = 1.5;
  vec2 grad = normalize(
      vec2(
          capsuleSdf(local + vec2(e, 0.0), center, r) -
              capsuleSdf(local - vec2(e, 0.0), center, r),
          capsuleSdf(local + vec2(0.0, e), center, r) -
              capsuleSdf(local - vec2(0.0, e), center, r)) +
      vec2(1e-5));

  // 位移剖面：带内半正弦——边缘与带内侧尽头都收敛到 0，中段达峰，
  // 峰值 = uAmount 的一半。采样点沿法线反方向（向内）偏移，内容被
  // 推向边缘，形成透镜的弯折感；只采样元素内部，不越界。
  float t = clamp(depth / uBand, 0.0, 1.0);
  float disp = uAmount * 0.5 * sin(t * 3.14159265);
  vec2 offset = -grad * disp;

  vec2 sampleUv = clamp((p + offset) / uSize, vec2(0.001), vec2(0.999));
  if (uChromatic < 0.5) {
    fragColor = texture(uTexture, sampleUv);
    return;
  }

  // 极轻色差：三通道沿同一偏移微量缩放。
  vec4 color;
  color.r = texture(uTexture, clamp((p + offset * 1.07) / uSize,
                                    vec2(0.001), vec2(0.999)))
                .r;
  color.g = texture(uTexture, sampleUv).g;
  color.b = texture(uTexture, clamp((p + offset * 0.93) / uSize,
                                    vec2(0.001), vec2(0.999)))
                .b;
  color.a = 1.0;
  fragColor = color;
}
