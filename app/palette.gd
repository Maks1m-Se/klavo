extends RefCounted
class_name AppPalette

const DARK := {
    "background": Color("121614"), "surface": Color("1c2220"), "raised": Color("26302c"),
    "text": Color("ecefea"), "muted": Color("8e9a93"), "line": Color("2e3833"),
    "accent": Color("a8c8b0"), "on_accent": Color("121614"), "soft": Color("2f4236"),
    "downbeat": Color("e8b04b"), "danger": Color("d96a50")
}
const LIGHT := {
    "background": Color("f4f5f0"), "surface": Color("e8ece7"), "raised": Color("dce4dd"),
    "text": Color("1a2520"), "muted": Color("4e5d55"), "line": Color("bdc9c0"),
    "accent": Color("315840"), "on_accent": Color("ffffff"), "soft": Color("d5e6d8"),
    "downbeat": Color("99620b"), "danger": Color("a33725")
}

static func colors(light: bool) -> Dictionary:
    return LIGHT if light else DARK
