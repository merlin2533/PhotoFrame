import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Result of the last crawl of one source: how many images it yielded and
/// when. Filled by the slideshow crawl, shown in the sources list.
class SourceStats {
  const SourceStats({required this.imageCount, required this.updatedAt});

  final int imageCount;
  final DateTime updatedAt;
}

class SourceStatsController extends Notifier<Map<String, SourceStats>> {
  @override
  Map<String, SourceStats> build() => const {};

  void record(String sourceId, int imageCount) {
    state = {
      ...state,
      sourceId: SourceStats(imageCount: imageCount, updatedAt: DateTime.now())
    };
  }
}

final NotifierProvider<SourceStatsController, Map<String, SourceStats>>
    sourceStatsProvider =
    NotifierProvider<SourceStatsController, Map<String, SourceStats>>(
        SourceStatsController.new);
