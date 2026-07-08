/// Cross-platform "share these bytes as a file". The implementation is chosen
/// by conditional export: native writes a temp file and shares its path; web
/// shares the bytes directly via the Web Share API. Returns true if the share
/// was not dismissed by the user.
library;

export 'share_io.dart' if (dart.library.js_interop) 'share_web.dart'
    show shareBytes;
