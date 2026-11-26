class_name Cards
extends RefCounted
## A standard 52 card deck shared by the card games. Cards are 0..51: rank = c % 13 + 1 (ace 1 .. king 13),
## suit = c / 13 (clubs, diamonds, hearts, spades). Card faces are drawn at runtime.

const SUITS := ["♣", "♦", "♥", "♠"]
const RANKS := ["", "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"]
const RED := Color(0.8, 0.1, 0.1)


static func rank(c: int) -> int:
	return c % 13 + 1


static func suit(c: int) -> int:
	return c / 13


static func card_name(c: int) -> String:
	return RANKS[rank(c)] + SUITS[suit(c)]


## The whole deck in an order fixed by key, so every peer deals the same cards from the same key.
static func shuffled(key: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = key.hash()
	var deck := range(52)
	for i in range(51, 0, -1):  # Fisher-Yates with our own rng
		var j := rng.randi_range(0, i)
		var tmp = deck[i]
		deck[i] = deck[j]
		deck[j] = tmp
	return deck


## A font with the suit symbols in it.
static func font() -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI Symbol", "Segoe UI", "Arial", "DejaVu Sans"])
	return f


## Draw card c in rect r on ci: face up, or its back. dim greys it out (can't be played).
static func draw(ci: CanvasItem, f: Font, r: Rect2, c: int, up := true, dim := false) -> void:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(int(r.size.x * 0.08))
	box.bg_color = Color("#fbfaf6") if up else Color("#2c4a8a")
	box.border_color = Color(0, 0, 0, 0.5)
	box.set_border_width_all(1)
	ci.draw_style_box(box, r)
	if not up:
		ci.draw_rect(r.grow(-r.size.x * 0.1), Color("#5a80c8"), false, 2)
		return
	var col := RED if suit(c) in [1, 2] else Color.BLACK
	var fs := int(r.size.x * 0.26)
	var corner := r.position + Vector2(r.size.x * 0.08, 0)
	ci.draw_string(f, corner + Vector2(0, fs * 1.1), RANKS[rank(c)], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	ci.draw_string(f, corner + Vector2(0, fs * 2.1), SUITS[suit(c)], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	ci.draw_string(f, Vector2(r.position.x, r.get_center().y + r.size.x * 0.25), SUITS[suit(c)],
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, int(r.size.x * 0.55), col)
	if dim:
		var shade := box.duplicate() as StyleBoxFlat
		shade.bg_color = Color(0, 0, 0, 0.4)
		shade.set_border_width_all(0)
		ci.draw_style_box(shade, r)
