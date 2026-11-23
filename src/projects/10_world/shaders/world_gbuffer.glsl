// G-buffer fragment shader for terrain, rocks, monoliths, clouds (vertex stage = builtin 'unlit').
// Writes: target 0 albedo + material id, target 1 world normal, target 2 world pos + linear depth.

layout(constant_id = 0) const bool flag_flatNormals = false; // low-poly look: one normal per triangle
layout(constant_id = 1) const bool flag_cloud = false;       // clip the bottom flat, fake a flat underside

uniform float material;
uniform float cloudBase;

layout(location = 1) out vec4 outNormal;
layout(location = 2) out vec4 outPos;

vec4 lovrmain() {
  vec3 toCam = CameraPositionWorld - PositionWorld;
  vec3 n = normalize(Normal);

  // Screen-space derivatives of the position lie in the triangle's plane -> their cross product is the face normal.
  if (flag_flatNormals) {
    n = normalize(cross(dFdx(PositionWorld), dFdy(PositionWorld)));
    if (dot(n, toCam) < 0.) n = -n;
  }

  // Clouds: cut everything under the base. Through the hole we see the inside (back faces) of the top half,
  // which we shade as if it were a flat bottom facing down.
  if (flag_cloud) {
    if (PositionWorld.y < cloudBase) discard;
    if (dot(n, toCam) < 0.) n = vec3(0, -1, 0);
  }

  vec3 albedo = Color.rgb;
  if (material == 3.) { // rock: wobbly horizontal strata
    vec3 p = PositionWorld;
    albedo *= .82 + .18 * sin(p.y * 1.3 + sin(p.x * .21 + p.z * .17) * 2.5);
  }

  outNormal = vec4(n, 0);
  outPos = vec4(PositionWorld, -(View * vec4(PositionWorld, 1)).z);
  return vec4(albedo, material / 255.);
}
