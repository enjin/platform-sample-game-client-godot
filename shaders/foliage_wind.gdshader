// Gentle wind sway for foliage, reproducing Unity's Material_Plants
// "MoveVertices" wind: the top of each sprite leans back and forth on a sine
// while the base stays planted. The lean is proportional to each vertex's
// height above the sprite's anchor, so it scales with sprite size (a fixed
// pixel lean is invisible on a ~1300px pine but obvious on a small bush) using
// a single shared material -- no per-instance uniforms (those overflow the
// GLES3 instance buffer with hundreds of plants).
//
// A per-instance phase from the world position keeps neighbours out of
// lockstep. Vertex-only, so the default fragment keeps the (normal-mapped)
// CanvasTexture and 2D lighting intact.
shader_type canvas_item;

uniform float wind_speed = 1.8;   // sway sine frequency (rad/sec)
uniform float lean = 0.04;        // fraction of height-above-base the top leans
uniform float gust = 0.35;        // slower secondary sine for an organic feel

void vertex() {
	// Foliage props/crops are bottom-anchored: the base sits at/below the local
	// origin (VERTEX.y >= 0) and the canopy rises above it (VERTEX.y < 0). So
	// height-above-base is max(0, -VERTEX.y): ~0 at the base, largest at the top.
	float above = max(0.0, -VERTEX.y);
	float phase = (MODEL_MATRIX[3].x + MODEL_MATRIX[3].y) * 0.04;
	float w = sin(TIME * wind_speed + phase)
		+ gust * sin(TIME * wind_speed * 0.37 + phase * 1.7);
	VERTEX.x += w * lean * above;
}
