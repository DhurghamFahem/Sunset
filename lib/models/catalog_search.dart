/// Keep these rules aligned with normalize_catalog_search in the database.
String normalizeCatalogSearch(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]'), '')
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

List<String> catalogSearchTerms(String value) =>
    normalizeCatalogSearch(value)
        .split(' ')
        .where((term) => term.isNotEmpty)
        .toSet()
        .toList();

List<String> parseCatalogTags(String value) {
  final seen = <String>{};
  return value
      .split(RegExp(r'[,،;؛\n]'))
      .map((tag) => tag.trim().replaceFirst(RegExp(r'^#+'), '').trim())
      .where(
        (tag) =>
            normalizeCatalogSearch(tag).isNotEmpty &&
            seen.add(normalizeCatalogSearch(tag)),
      )
      .toList();
}
