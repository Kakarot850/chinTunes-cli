import 'package:chintunes_core/chintunes_core.dart';
import 'package:test/test.dart';

void main() {
  group('JioSaavnCrypto.decryptMediaUrl', () {
    test('decrypts a known DES-ECB vector (generated with pycryptodomex)', () {
      // DES-ECB(key "38346591", PKCS5) of "https://aac.saavncdn.com/123/abcdef_96.mp4"
      const vector = 'ID2ieOjCrwfgWvL5sXl4B1ImC5QfbsDyQd+aqn5Yzr3aGttEjbIm9m+XHLUinhCK';
      expect(
        JioSaavnCrypto.decryptMediaUrl(vector),
        'https://aac.saavncdn.com/123/abcdef_96.mp4',
      );
    });

    test('decrypts a live encrypted_media_url captured from search.getResults', () {
      const live =
          'ID2ieOjCrwfgWvL5sXl4B1ImC5QfbsDyRofh8YQPTqjR2tIxTYXqGEQHgqnNfsetouo4rsD0s4RZKObWAyHrEhw7tS9a8Gtq';
      expect(
        JioSaavnCrypto.decryptMediaUrl(live),
        'https://aac.saavncdn.com/430/5c5ea5cc00e3bff45616013226f376fe_96.mp4',
      );
    });

    test('returns null for empty or garbage input', () {
      expect(JioSaavnCrypto.decryptMediaUrl(null), isNull);
      expect(JioSaavnCrypto.decryptMediaUrl(''), isNull);
      expect(JioSaavnCrypto.decryptMediaUrl('not base64 !!'), isNull);
    });
  });

  group('JioSaavnCrypto.withBitrate', () {
    const base = 'https://aac.saavncdn.com/430/abc_96.mp4';

    test('swaps rendition suffix', () {
      expect(JioSaavnCrypto.withBitrate(base, 320), 'https://aac.saavncdn.com/430/abc_320.mp4');
      expect(JioSaavnCrypto.withBitrate(base, 160), 'https://aac.saavncdn.com/430/abc_160.mp4');
      expect(
        JioSaavnCrypto.withBitrate('https://x/abc_320.mp4', 96),
        'https://x/abc_96.mp4',
      );
    });

    test('appends suffix when missing (CLI upgrade_to_320k parity)', () {
      expect(JioSaavnCrypto.withBitrate('https://x/abc.mp4', 320), 'https://x/abc_320.mp4');
    });

    test('leaves non-mp4 urls untouched', () {
      expect(JioSaavnCrypto.withBitrate('https://x/abc.mp3', 320), 'https://x/abc.mp3');
    });
  });
}
