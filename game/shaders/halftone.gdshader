shader_type canvas_item;

// Dynamischer Halbtonraster-Effekt: liest den bisher gezeichneten Bildschirm
// (alles ausser dem Einstellungsmenue) und ersetzt ihn durch ein Raster aus
// farbigen Punkten auf einem Papierton. Die Punktgroesse folgt der Helligkeit
// jedes Farbkanals; die Kanaele koennen gegeneinander verdreht werden, wodurch
// der typische Riso-/Farbtrennungseindruck entsteht.
//
// Der Effekt liegt als bildschirmfuellendes Rechteck ueber dem Spiel. Alle
// Uniforms kommen aus GameConfig und werden ohne Neustart uebernommen.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

// Rasterweite (Abstand der Punkte) in Fensterpixeln.
uniform float u_dot_size = 6.0;
// Drehung des Rasters in Grad.
uniform float u_angle = 15.0;
// Punktwachstum: vergroessert oder verkleinert alle Punkte.
uniform float u_gain = 1.0;
// Kontrast der Helligkeit vor dem Rastern.
uniform float u_contrast = 1.0;
// Weichheit der Punktkanten (0 = hart, 1 = sehr weich).
uniform float u_softness = 0.3;
// Farbtrennung: zusaetzliche Drehung zwischen den Farbkanaelen.
uniform float u_separation = 1.0;
// Papieranteil in den Zwischenraeumen (0 = Originalfarbe, 1 = Papierton).
uniform float u_paper = 0.75;
// Gesamtstaerke: mischt das Ergebnis mit dem unveraenderten Bild.
uniform float u_amount = 1.0;

// Fester Papierton der Zwischenraeume (warmes Offwhite).
const vec3 PAPER_COLOR = vec3(0.949, 0.918, 0.847);
// Radiusfaktor fuer flaechentreue Punkte: r = cell * K * sqrt(dichte).
// K = 1/sqrt(PI) schliesst bei voller Dichte die Flaeche.
const float DOT_RADIUS = 0.5641895835477563;
// Abstand der Kanalwinkel bei voller Farbtrennung (Grad).
const float SEPARATION_STEP = 30.0;

// Cosinus/Sinus der drei Kanalwinkel, im Vertex-Shader berechnet: die Winkel
// sind pro Zeichnung konstant, so entfallen die Trigonometrie-Aufrufe pro Pixel.
varying vec2 v_channel0;
varying vec2 v_channel1;
varying vec2 v_channel2;

void vertex() {
	float spread = u_separation * SEPARATION_STEP;
	v_channel0 = vec2(cos(radians(u_angle)), sin(radians(u_angle)));
	v_channel1 = vec2(cos(radians(u_angle + spread)), sin(radians(u_angle + spread)));
	v_channel2 = vec2(cos(radians(u_angle + spread * 2.0)), sin(radians(u_angle + spread * 2.0)));
}

vec2 rotate_pixel(vec2 pixel, vec2 cos_sin) {
	return vec2(cos_sin.x * pixel.x - cos_sin.y * pixel.y,
		cos_sin.y * pixel.x + cos_sin.x * pixel.y);
}

// Deckung eines Rasterpunktes (0..1) fuer eine Farbdichte an dieser Stelle.
float dot_coverage(vec2 pixel, float density, vec2 cos_sin, float cell) {
	vec2 p = rotate_pixel(pixel, cos_sin);
	vec2 center = (floor(p / cell) + 0.5) * cell;
	float radius = cell * DOT_RADIUS * sqrt(clamp(density * u_gain, 0.0, 1.0));
	float edge = max(u_softness * cell * 0.5, 0.5);
	return 1.0 - smoothstep(radius - edge, radius + edge, distance(p, center));
}

void fragment() {
	vec4 src = texture(screen_texture, SCREEN_UV);
	vec3 color = src.rgb;

	// Helligkeit je Kanal in eine Punktdichte umrechnen und spreizen.
	vec3 density = clamp((1.0 - color - 0.5) * u_contrast + 0.5, 0.0, 1.0);

	float cell = max(u_dot_size, 1.0);
	vec2 pixel = FRAGCOORD.xy;
	vec3 coverage;
	coverage.r = dot_coverage(pixel, density.r, v_channel0, cell);
	coverage.g = dot_coverage(pixel, density.g, v_channel1, cell);
	coverage.b = dot_coverage(pixel, density.b, v_channel2, cell);

	// Zwischenraeume werden Richtung Papierton aufgehellt, die Punkte tragen
	// die Originalfarbe.
	vec3 gap = mix(color, PAPER_COLOR, u_paper);
	vec3 raster = mix(gap, color, coverage);

	COLOR = vec4(mix(color, raster, u_amount), src.a);
}
