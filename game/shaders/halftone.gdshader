shader_type canvas_item;

// CMYK-Halbton nach dem "Canvas Item Halftone Shader" von OskarGosbol
// (godotshaders.com, MIT-Lizenz). Fuer Godot 4 als bildschirmweiter Effekt
// portiert: nur der Bildschirmmodus, ohne Objektraum und ohne einstellbare
// Druckfarben. Statt der mitgelieferten Muster-Textur wird das Streumuster
// entweder im Skript erzeugt oder als PNG geladen (siehe halftone_overlay.gd).
//
// Der bereits gezeichnete Bildschirm wird in CMYK zerlegt. Jede Druckfarbe
// bekommt ein eigenes, gedrehtes Punktraster; die Punktschwelle kommt aus der
// wiederholten Muster-Textur. Die Farbauszuege koennen zusaetzlich verdreht
// werden, wodurch der typische Druckversatz entsteht.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
// Streumuster, wird ueber den Bildschirm wiederholt.
uniform sampler2D u_pattern : repeat_enable, filter_linear;
// Rauschtextur: ihre RGBA-Kanaele variieren die Deckkraft der vier Druckfarben.
uniform sampler2D u_noise : repeat_enable, filter_linear;

// Anzahl der Musterwiederholungen ueber den Bildschirm.
uniform float u_pattern_scaling : hint_range(0.05, 24.0) = 6.0;
// Qualitaet der Mehrfachabtastung (hoeher = glatter, aber langsamer).
uniform float u_sampling_quality : hint_range(0.05, 1.0) = 0.5;

// Rasterwinkel je Druckfarbe in Grad.
uniform float u_cyan_rotation : hint_range(-180.0, 180.0) = 0.0;
uniform float u_magenta_rotation : hint_range(-180.0, 180.0) = 15.0;
uniform float u_yellow_rotation : hint_range(-180.0, 180.0) = 30.0;
uniform float u_black_rotation : hint_range(-180.0, 180.0) = 45.0;

// Zusaetzlicher Farbauszug je Druckfarbe in Grad.
uniform float u_cyan_offset_rotation : hint_range(-180.0, 180.0) = 0.0;
uniform float u_magenta_offset_rotation : hint_range(-180.0, 180.0) = 0.0;
uniform float u_yellow_offset_rotation : hint_range(-180.0, 180.0) = 0.0;
uniform float u_black_offset_rotation : hint_range(-180.0, 180.0) = 0.0;

// Helligkeitsschwelle, unter der Bildpunkte als durchsichtig gelten.
uniform float u_alpha_threshold : hint_range(0.0, 1.0) = 0.5;

// Druckdeckkraft je Druckfarbe (0 = kein Auftrag, 1 = volle Deckung).
uniform float u_cyan_ink : hint_range(0.0, 1.0) = 1.0;
uniform float u_magenta_ink : hint_range(0.0, 1.0) = 1.0;
uniform float u_yellow_ink : hint_range(0.0, 1.0) = 1.0;
uniform float u_black_ink : hint_range(0.0, 1.0) = 1.0;

// Rauschen auf der Deckkraft je Druckfarbe: 0 = gleichmaessig, 1 = voll vom
// Muster bestimmt. Weite und Staerke sind je Kanal einstellbar.
uniform float u_cyan_noise_strength : hint_range(0.0, 1.0) = 0.0;
uniform float u_magenta_noise_strength : hint_range(0.0, 1.0) = 0.0;
uniform float u_yellow_noise_strength : hint_range(0.0, 1.0) = 0.0;
uniform float u_black_noise_strength : hint_range(0.0, 1.0) = 0.0;
// Wiederholungen der Rauschtextur ueber den Bildschirm, je Druckfarbe.
uniform float u_cyan_noise_scaling : hint_range(0.05, 24.0) = 4.0;
uniform float u_magenta_noise_scaling : hint_range(0.05, 24.0) = 4.0;
uniform float u_yellow_noise_scaling : hint_range(0.05, 24.0) = 4.0;
uniform float u_black_noise_scaling : hint_range(0.05, 24.0) = 4.0;

// Feste Druckfarben und Papierton.
const vec3 PAPER_COLOR = vec3(1.0, 1.0, 1.0);
const vec3 CYAN_COLOR = vec3(0.0, 1.0, 1.0);
const vec3 MAGENTA_COLOR = vec3(1.0, 0.0, 1.0);
const vec3 YELLOW_COLOR = vec3(1.0, 1.0, 0.0);
const vec3 BLACK_COLOR = vec3(0.0, 0.0, 0.0);

vec2 rotate_uv(vec2 uv, float angle) {
	float a = radians(angle);
	float s = sin(a);
	float c = cos(a);
	return vec2(c * uv.x - s * uv.y, s * uv.x + c * uv.y);
}

vec4 one_pass(vec2 tl_uv, vec2 tr_uv, vec2 bl_uv, vec2 br_uv, vec2 local_uv, vec2 screen_size) {
	vec2 top_uv = mix(tl_uv, tr_uv, local_uv.x);
	vec2 bot_uv = mix(bl_uv, br_uv, local_uv.x);
	vec2 pass_uv = mix(top_uv, bot_uv, local_uv.y);

	// Farbauszug: jede Druckfarbe tastet den Bildschirm leicht verdreht ab.
	vec2 c_uv = rotate_uv(pass_uv, u_cyan_offset_rotation);
	vec2 m_uv = rotate_uv(pass_uv, u_magenta_offset_rotation);
	vec2 y_uv = rotate_uv(pass_uv, u_yellow_offset_rotation);
	vec2 k_uv = rotate_uv(pass_uv, u_black_offset_rotation);

	vec4 c_base = texture(screen_texture, c_uv);
	vec4 m_base = texture(screen_texture, m_uv);
	vec4 y_base = texture(screen_texture, y_uv);
	vec4 k_base = texture(screen_texture, k_uv);

	// RGB in CMYK umrechnen (Quelle: rapidtables.com/convert/color/rgb-to-cmyk).
	float c_k = 1.0 - max(max(c_base.r, c_base.g), c_base.b);
	float m_k = 1.0 - max(max(m_base.r, m_base.g), m_base.b);
	float y_k = 1.0 - max(max(y_base.r, y_base.g), y_base.b);
	float k = 1.0 - max(max(k_base.r, k_base.g), k_base.b);

	float c = (1.0 - c_base.r - c_k) / max(1.0 - c_k, 0.0001);
	float m = (1.0 - m_base.g - m_k) / max(1.0 - m_k, 0.0001);
	float y = (1.0 - y_base.b - y_k) / max(1.0 - y_k, 0.0001);
	float a = texture(screen_texture, pass_uv).a < u_alpha_threshold ? 0.0 : 1.0;

	// Punktschwelle je Druckfarbe aus dem gedrehten, wiederholten Muster.
	vec2 pattern_size = vec2(textureSize(u_pattern, 0));
	vec2 pattern_uv = pass_uv * screen_size / pattern_size * u_pattern_scaling;
	float c_threshold = texture(u_pattern, rotate_uv(pattern_uv, u_cyan_rotation)).r;
	float m_threshold = texture(u_pattern, rotate_uv(pattern_uv, u_magenta_rotation)).r;
	float y_threshold = texture(u_pattern, rotate_uv(pattern_uv, u_yellow_rotation)).r;
	float k_threshold = texture(u_pattern, rotate_uv(pattern_uv, u_black_rotation)).r;

	// Deckkraft je Druckfarbe. Die Rauschtextur wird je Kanal mit eigener Weite
	// abgetastet; jeder Farbkanal steuert eine Druckfarbe, damit ein Druck mit
	// wenig und ungleichmaessiger Farbe entsteht.
	float c_noise = texture(u_noise, pass_uv * u_cyan_noise_scaling).r;
	float m_noise = texture(u_noise, pass_uv * u_magenta_noise_scaling).g;
	float y_noise = texture(u_noise, pass_uv * u_yellow_noise_scaling).b;
	float k_noise = texture(u_noise, pass_uv * u_black_noise_scaling).a;
	float c_ink = u_cyan_ink * mix(1.0, c_noise, u_cyan_noise_strength);
	float m_ink = u_magenta_ink * mix(1.0, m_noise, u_magenta_noise_strength);
	float y_ink = u_yellow_ink * mix(1.0, y_noise, u_yellow_noise_strength);
	float k_ink = u_black_ink * mix(1.0, k_noise, u_black_noise_strength);

	// Papier beginnt weiss; jede Druckfarbe zieht ihre Komplementfarbe ab.
	vec3 paper = PAPER_COLOR;
	if (c > c_threshold && c_uv.x >= 0.0 && c_uv.x <= 1.0 && c_uv.y >= 0.0 && c_uv.y <= 1.0) {
		paper -= (PAPER_COLOR - CYAN_COLOR) * c_ink;
	}
	if (m > m_threshold && m_uv.x >= 0.0 && m_uv.x <= 1.0 && m_uv.y >= 0.0 && m_uv.y <= 1.0) {
		paper -= (PAPER_COLOR - MAGENTA_COLOR) * m_ink;
	}
	if (y > y_threshold && y_uv.x >= 0.0 && y_uv.x <= 1.0 && y_uv.y >= 0.0 && y_uv.y <= 1.0) {
		paper -= (PAPER_COLOR - YELLOW_COLOR) * y_ink;
	}
	if (k > k_threshold && k_uv.x >= 0.0 && k_uv.x <= 1.0 && k_uv.y >= 0.0 && k_uv.y <= 1.0) {
		paper -= (PAPER_COLOR - BLACK_COLOR) * k_ink;
	}
	return vec4(paper, a);
}

void fragment() {
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	// Die vier Ecken des aktuellen Bildpunktes fuer die Mehrfachabtastung.
	vec2 tl_uv = SCREEN_UV + vec2(0.5, 0.5) * SCREEN_PIXEL_SIZE;
	vec2 tr_uv = SCREEN_UV + vec2(0.5, -0.5) * SCREEN_PIXEL_SIZE;
	vec2 bl_uv = SCREEN_UV + vec2(-0.5, 0.5) * SCREEN_PIXEL_SIZE;
	vec2 br_uv = SCREEN_UV + vec2(-0.5, -0.5) * SCREEN_PIXEL_SIZE;

	int samples = int(ceil(u_pattern_scaling * u_sampling_quality));
	int sqrt_samples = int(ceil(sqrt(float(samples))));
	samples = sqrt_samples * sqrt_samples;
	float denom = max(float(sqrt_samples - 1), 1.0);
	vec4 sum = vec4(0.0);
	for (int x = 0; x < sqrt_samples; x++) {
		for (int y = 0; y < sqrt_samples; y++) {
			vec2 local_uv = vec2(float(x), float(y)) / denom;
			if (sqrt_samples == 1) {
				local_uv = vec2(0.5);
			}
			sum += one_pass(tl_uv, tr_uv, bl_uv, br_uv, local_uv, screen_size);
		}
	}
	COLOR = sum / float(samples);
}
