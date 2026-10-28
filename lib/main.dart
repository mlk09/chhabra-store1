import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

void main() {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();

      // A broken widget shows a small message instead of a red/grey screen.
      ErrorWidget.builder = (details) => Material(
        color: Colors.transparent,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              kReleaseMode ? 'Something went wrong here.' : details.exceptionAsString(),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
      };

      // Nothing slow happens before the first frame: storage + server connect
      // run inside the app (bootstrapProvider) with timeouts and a Retry screen.
      runApp(
        ProviderScope(
          retry: (_, _) => null, // we show our own Retry buttons
          child: const KiranaApp(),
        ),
      );
    },
    (error, stack) {
      debugPrint('Uncaught: $error\n$stack');
    },
  );
}
