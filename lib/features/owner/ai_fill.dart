import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../data/backend.dart';
import '../../data/models/product_guess.dart';

/// Sends a compressed photo to the AI and shows a small "reading…" dialog.
/// Returns null (after showing the reason) when it could not be read.
Future<ProductGuess?> readPhotoWithAi(BuildContext context, WidgetRef ref, ProductPhoto photo) async {
  final catalog = ref.read(catalogProvider).value;
  if (catalog == null) return null;
  final nav = Navigator.of(context, rootNavigator: true);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(ctx.tr('Reading the photo…', 'फ़ोटो पढ़ रहे हैं…'))),
            ],
          ),
        ),
      ),
    ),
  );
  var open = true;
  void close() {
    if (open) {
      open = false;
      nav.pop();
    }
  }

  try {
    final guess = await ref
        .read(backendProvider)
        .identifyProduct(shopId: catalog.shop.id, jpeg: photo.full, categories: catalog.categories);
    close();
    return guess;
  } catch (e) {
    close();
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('Could not read the photo', 'फ़ोटो नहीं पढ़ पाए')),
          content: Text(e is AppException ? ctx.pick(e.message, e.messageHi) : e.toString()),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    }
    return null;
  }
}
