// Animated pond water, replacing the flat tiled water sprite. Reproduces the
// look of Unity's ShaderGraph_Water / Material_Water: a translucent blue
// surface (deep->shallow gradient) with drifting wave highlights, letting the
// underwater tiles below show through. Procedural from WORLD position so it's
// seamless across all the water tiles (not per-tile). The tile texture is
// ignored -- the surface is generated here.
shader_type canvas_item;

uniform vec3 deep_color : source_color = vec3(0.270, 0.550, 1.0);
uniform vec3 shallow_color : source_color = vec3(0.440, 0.671, 1.0);
uniform vec3 highlight_color : source_color = vec3(0.620, 0.800, 1.0);
uniform float water_alpha = 0.62;   // matches Unity _Transparency ~0.53
uniform float wave_speed = 0.5;
uniform float wave_scale = 0.018;   // world-space frequency

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 p = world_pos * wave_scale;
	float t = TIME * wave_speed;
	// a few layered sines drifting in different directions = a moving surface
	float w1 = sin(p.x * 1.3 + p.y * 0.8 + t);
	float w2 = sin(p.x * 0.7 - p.y * 1.4 + t * 0.85);
	float w3 = sin(p.x * 2.4 + p.y * 1.9 - t * 1.2);
	float w = (w1 + 0.7 * w2 + 0.4 * w3) / 2.1;          // ~ -1..1
	vec3 col = mix(deep_color, shallow_color, w * 0.5 + 0.5);
	// faint, THIN crest glints only at the very tops of the waves -- a broad
	// smoothstep here makes big soft white blobs that read as "clouds".
	float crest = smoothstep(0.90, 0.99, w);
	crest = crest * crest * crest;                       // sharpen to a thin line
	col = mix(col, highlight_color, crest * 0.35);
	float a = mix(water_alpha, min(1.0, water_alpha + 0.12), crest);
	COLOR = vec4(col, a);
}
