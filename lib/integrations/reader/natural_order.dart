/// Compares strings the way a human expects: `page2` sorts before `page10`.
class NaturalOrder {
  static int compare(String a, String b) {
    var i = 0, j = 0;
    while (i < a.length && j < b.length) {
      final ca = a.codeUnitAt(i);
      final cb = b.codeUnitAt(j);
      if (_isDigit(ca) && _isDigit(cb)) {
        var ni = i, nj = j;
        while (ni < a.length && _isDigit(a.codeUnitAt(ni))) {
          ni++;
        }
        while (nj < b.length && _isDigit(b.codeUnitAt(nj))) {
          nj++;
        }
        final na = int.parse(a.substring(i, ni));
        final nb = int.parse(b.substring(j, nj));
        if (na != nb) return na.compareTo(nb);
        i = ni;
        j = nj;
        continue;
      }
      final la = ca | 0x20;
      final lb = cb | 0x20;
      if (la != lb) return la.compareTo(lb);
      i++;
      j++;
    }
    return (a.length - i).compareTo(b.length - j);
  }

  static bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

  static List<String> sorted(Iterable<String> values) {
    final list = values.toList()..sort(compare);
    return list;
  }
}
