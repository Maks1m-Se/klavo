extends RefCounted
class_name AppPalette

# App accents can be replaced independently of the classical piano keys.
const DARK := {
    "background": Color("14161a"), "surface": Color("23262c"),
    "text": Color("f5f5f5"), "muted": Color("a9adb6"),
    "line": Color("454951"), "accent": Color("dddddf"),
    "on_accent": Color("17181c"), "soft": Color("35383f")
}
const LIGHT := {
    "background": Color("f6f6f7"), "surface": Color("e9eaed"),
    "text": Color("202127"), "muted": Color("5c606b"),
    "line": Color("b9bec8"), "accent": Color("343740"),
    "on_accent": Color("ffffff"), "soft": Color("d9dce3")
}

static func colors(light: bool) -> Dictionary:
    return LIGHT if light else DARK
