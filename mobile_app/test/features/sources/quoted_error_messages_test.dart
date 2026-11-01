import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/observability/error_reporter.dart';
import 'package:mobile_app/features/sources/domain/photo_folder.dart';
import 'package:mobile_app/features/sources/local/local_folder_source.dart';
import 'package:mobile_app/features/sources/mock/mock_photo_source.dart';

/// Error messages are scrubbed before they reach GlitchTip. The scrubber
/// only redacts a value that is quoted or follows a keyword, so every
/// interpolated path, id or host in an error message must stay quoted.
/// These tests fail if a future edit drops the quotes.
void main() {
  test('local folder not found message quotes the root path', () async {
    const root = '/nonexistent/photoframe-test/Fotos';
    final source = LocalFolderSource(id: 'local-q', rootPath: root);
    addTearDown(source.dispose);

    final result = await source.testConnection();
    final message = result.failureOrNull!.message;

    expect(message, contains('"$root"'));
    expect(scrubSensitiveText(message), isNot(contains(root)));
  });

  test('mock unknown folder message quotes the id', () async {
    final source = MockPhotoSource(
      id: 'mock-q',
      displayName: 'Mock',
      folderCount: 1,
      itemsPerFolder: 1,
      simulatedDelay: Duration.zero,
    );
    addTearDown(source.dispose);

    const folder = PhotoFolder(id: 'nope-folder', name: 'x', path: '/x');
    final messages = await source
        .listImages(folder)
        .where((r) => r.isErr)
        .map((r) => r.failureOrNull!.message)
        .toList();

    expect(messages, hasLength(1));
    expect(messages.single, contains('"nope-folder"'));
  });
}
