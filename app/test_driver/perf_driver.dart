// Runs the performance test and writes build/<name>.timeline_summary.json.
//   flutter drive --driver=test_driver/perf_driver.dart --target=integration_test/scroll_perf_test.dart \
//     --profile --dart-define=DEV_USER=dev --dart-define=API_BASE_URL=http://localhost:3000 -d <device>  (phone: adb reverse tcp:3000 tcp:3000 first)
// The backend must be running (npm start in app/backend). Use --profile: debug builds are far slower than a real install.

import 'package:flutter_driver/flutter_driver.dart' as driver;
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() {
  return integrationDriver(
    responseDataCallback: (data) async {
      if (data == null) return;
      for (final key in ['home_scroll', 'discover_grid', 'discover_swipes']) {
        final raw = data[key];
        if (raw == null) continue;
        final timeline = driver.Timeline.fromJson(raw as Map<String, dynamic>);
        final summary = driver.TimelineSummary.summarize(timeline);
        await summary.writeTimelineToFile(key, pretty: true, includeSummary: true);
      }
    },
  );
}
