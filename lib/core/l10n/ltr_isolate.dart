/// Wraps a left-to-right fragment (URL, path, command, `|`) in LRI/PDI so it
/// keeps its order inside right-to-left text. Pass the result as a placeholder
/// value; the ARB files carry no raw bidi code points.
String ltrIsolate(String text) =>
    '${String.fromCharCode(0x2066)}$text${String.fromCharCode(0x2069)}';
