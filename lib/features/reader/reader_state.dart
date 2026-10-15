// Shared reader helpers kept in one place so every viewer behaves the same.

/// Fits a page into the viewport:
///  * `width` — fit to screen width (good for text-heavy pages)
///  * `height` — fit to screen height (good for tall scans)
///  * `contain` — show the whole page
enum FitMode { width, height, contain }

enum ReadingDirection { leftToRight, rightToLeft }

/// Human label for a reading direction, used in the settings sheet.
String directionLabel(ReadingDirection d) =>
    d == ReadingDirection.rightToLeft ? 'Right to left (manga)' : 'Left to right';
