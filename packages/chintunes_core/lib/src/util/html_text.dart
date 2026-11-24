/// Minimal HTML entity unescaping, equivalent to Python's `html.unescape`
/// for the entities JioSaavn actually emits (`&quot;`, `&amp;`, `&#039;`...).
String unescapeHtml(String? input) {
  if (input == null || input.isEmpty) return '';
  var s = input;
  s = s.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (m) => String.fromCharCode(int.parse(m[1]!)),
  );
  s = s.replaceAllMapped(
    RegExp(r'&#x([0-9a-fA-F]+);'),
    (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
  );
  // `&amp;` must be last so `&amp;quot;` decodes to `&quot;` (single pass).
  const named = <String, String>{
    '&quot;': '"',
    '&apos;': "'",
    '&lt;': '<',
    '&gt;': '>',
    '&nbsp;': ' ',
    '&amp;': '&',
  };
  named.forEach((k, v) => s = s.replaceAll(k, v));
  return s.trim();
}

/// Converts JioSaavn's `<br>`-separated lyrics into newline text.
String brToNewlines(String input) =>
    input.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
