// Shell grass, vertex stage. The terrain mesh is drawn `shellCount` times (instancing);
// instance i is pushed up along the normal to height (i+1)/shellCount * shellHeight.
// Each shell is a thin horizontal slice through every blade; the fragment shader decides which pixels are "blade".

uniform float shellCount;
uniform float shellHeight;

vec4 lovrmain() {
  float h = float(InstanceIndex + 1) / shellCount; // 0..1 up the blade
  vec3 n = normalize(VertexNormal);                 // terrain is drawn untransformed: local = world
  vec3 p = VertexPosition.xyz + n * h * shellHeight;

  // Wind: rolling gust waves + small flutter, bending more towards the tip (h^2).
  vec2 dir = normalize(vec2(1, .4));
  float gust = .5 + .5 * sin(dot(p.xz, dir) * .07 - Time * 1.6);
  float flutter = sin(Time * 3.1 + p.x * .9 + p.z * .7);
  p.xz += (dir * (.15 + .45 * gust) + .05 * flutter) * h * h * shellHeight;

  PositionWorld = p;
  Normal = n;
  UV = vec2(h, gust);
  return ViewProjection * vec4(p, 1);
}
