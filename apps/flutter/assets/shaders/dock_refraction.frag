#version 320 es
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform sampler2D uTexture;
uniform vec2 uSize;        // 元素尺寸（物理像素）
uniform float uBand;       // 折射带宽 refractionHeight（物理像素）
uniform float uAmount;     // 折射量 refractionAmount（物理像素，正值；
                           // 内部按 Kyant 约定取负，向内采样防越界）
uniform float uDispersion; // 色散强度（0=关，单采样快路径；>0 沿折射
                           // 方向做 7 段光谱采样，Kyant 典型 0.2）
uniform float uRim;        // 边缘镜面高光强度（0=关）
uniform float uInnerShadow; // 底部内阴影强度（0=关）

out vec4 fragColor;

// 胶囊（圆角 = 短边一半的 stadium）带符号距离场：内部为负、边缘为 0。
float capsuleSdf(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - (halfSize - vec2(r));
  return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// Kyant gradSdRoundedRect 的解析梯度（胶囊版）：圆角区沿角点径向，
// 直边区沿近边法线。gradRadius 按 Kyant 在放大 1.5 倍半径的形状上求
// （胶囊半径已达短边一半，gradRadius 恒等于 r，此式保留 Kyant 原式）。
vec2 capsuleGrad(vec2 p, vec2 halfSize, float r) {
  vec2 cornerCoord = abs(p) - (halfSize - vec2(r));
  if (cornerCoord.x >= 0.0 || cornerCoord.y >= 0.0) {
    return sign(p) *
        normalize(max(cornerCoord, vec2(0.0)) + vec2(1e-5));
  }
  float gx = step(cornerCoord.y, cornerCoord.x);
  return sign(p) * vec2(gx, 1.0 - gx);
}

// Kyant circleMap：球面透镜的位移剖面——边缘处斜率最大、弯光最强，
// 向内按圆弧衰减到 0。（miuix14/15 的半正弦剖面恰好反了：边缘为 0、
// 带中间峰值，真实玻璃弯光最强处反而不弯，是「假」的主因。）
float circleMap(float x) {
  return 1.0 - sqrt(1.0 - x * x);
}

vec4 sampleAt(vec2 coordPx) {
  return texture(uTexture,
      clamp(coordPx / uSize, vec2(0.001), vec2(0.999)));
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 uv = p / uSize;
  vec2 halfSize = uSize * 0.5;
  vec2 local = p - halfSize;
  float r = min(halfSize.x, halfSize.y);
  float sd = capsuleSdf(local, halfSize, r);
  float depth = -sd; // 距边缘的深度（内部 ≥ 0）

  // 带外（深处）与元素外不折射、也无边缘光学。
  if (depth < 0.0 || depth >= uBand || uBand <= 0.0 || uAmount <= 0.0) {
    fragColor = texture(uTexture, uv);
    return;
  }

  float gradRadius = min(r * 1.5, min(halfSize.x, halfSize.y));
  vec2 grad = capsuleGrad(local, halfSize, gradRadius);
  // depthEffect = 0（Kyant 默认）：梯度不混入中心向。
  // d 为负（refractionAmount 传入负值是 Kyant 的约定）：采样点沿
  // 外法线反方向（向内）偏移 |d|，边缘内容被向内拉、呈透镜弯折。
  float d = -circleMap(1.0 - depth / uBand) * uAmount;
  vec2 refractOffset = d * grad;
  vec2 refractedCoord = p + refractOffset;

  vec4 color;
  if (uDispersion <= 0.0) {
    color = sampleAt(refractedCoord);
  } else {
    // Kyant/BiliPai 的 7 段光谱色散（权重照其 /3.5、/7、/3 分段法）：
    // 沿折射方向以 +1、+2/3、+1/3、0、−1/3、−2/3、−1 倍偏移采样，
    // 按光谱分段累积通道。偏移 ∝ d 本身，色散自然集中在边缘带。
    vec2 dispersed = refractOffset * uDispersion;
    vec4 acc = vec4(0.0);

    vec4 tap = sampleAt(refractedCoord + dispersed);
    acc.r += tap.r / 3.5;
    acc.a += tap.a / 7.0;

    tap = sampleAt(refractedCoord + dispersed * (2.0 / 3.0));
    acc.r += tap.r / 3.5;
    acc.g += tap.g / 7.0;
    acc.a += tap.a / 7.0;

    tap = sampleAt(refractedCoord + dispersed * (1.0 / 3.0));
    acc.r += tap.r / 3.5;
    acc.g += tap.g / 3.5;
    acc.a += tap.a / 7.0;

    tap = sampleAt(refractedCoord);
    acc.g += tap.g / 3.5;
    acc.a += tap.a / 7.0;

    tap = sampleAt(refractedCoord - dispersed * (1.0 / 3.0));
    acc.g += tap.g / 3.5;
    acc.b += tap.b / 3.0;
    acc.a += tap.a / 7.0;

    tap = sampleAt(refractedCoord - dispersed * (2.0 / 3.0));
    acc.b += tap.b / 3.0;
    acc.a += tap.a / 7.0;

    tap = sampleAt(refractedCoord - dispersed);
    acc.r += tap.r / 7.0;
    acc.b += tap.b / 3.0;
    acc.a += tap.a / 7.0;

    color = acc;
  }

  // 边缘带内的横截面权重：边缘最强、向内衰减（与 circleMap 同族）。
  float bandW = 1.0 - depth / uBand;

  // 边缘镜面光：SDF 梯度与固定顶部光向的点积——顶部边缘最亮，
  // 两侧保留三成底光勾勒轮廓（近似 BiliPai 的 BloomStroke 高光；
  // 其重力感应跟随不做，固定顶部光源）。
  if (uRim > 0.0) {
    float facing = max(dot(grad, vec2(0.0, -1.0)), 0.0);
    float rim = uRim * pow(bandW, 1.5) * (0.35 + 0.65 * facing);
    color.rgb += vec3(rim) * 0.6;
  }

  // 底部内阴影：边缘带内、越靠底部越暗，给玻璃压出厚度感。
  if (uInnerShadow > 0.0) {
    float bottomness = smoothstep(0.1, 1.0, local.y / halfSize.y);
    float shade = uInnerShadow * bandW * bottomness * 0.5;
    color.rgb *= (1.0 - shade);
  }

  fragColor = color;
}
