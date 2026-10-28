import 'package:flutter/material.dart';

import '../../data/backend.dart';
import '../i18n.dart';

/// A friendly message for any error (Hindi when the app is in Hindi).
String errorText(BuildContext context, Object error) {
  if (error is AppException) return context.pick(error.message, error.messageHi);
  final s = error.toString();
  if (s.contains('SocketException') || s.contains('Failed host lookup') || s.contains('ClientException')) {
    return context.tr('No internet connection.', 'इंटरनेट कनेक्शन नहीं है।');
  }
  return context.tr('Something went wrong. Please try again.', 'कुछ गड़बड़ हुई। फिर से कोशिश करें।');
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: error ? scheme.onError : null)),
        backgroundColor: error ? scheme.error : null,
      ),
    );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator());
}

class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: t.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: t.textTheme.titleLarge, textAlign: TextAlign.center),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
            if (onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel ?? '')),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => MessageView(
    icon: Icons.cloud_off_rounded,
    title: context.tr('Could not load', 'लोड नहीं हो पाया'),
    message: errorText(context, error),
    actionLabel: context.tr('Try again', 'फिर से कोशिश करें'),
    onAction: onRetry,
  );
}

/// Shop logo: saffron/green monogram, no image file needed.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1FA45A), Color(0xFF0E7A3E)],
        ),
        boxShadow: [BoxShadow(color: const Color(0xFF1FA45A).withValues(alpha: 0.35), blurRadius: size * 0.3)],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'C',
            style: TextStyle(
              fontSize: size * 0.58,
              height: 1,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              fontFamily: 'Mukta',
            ),
          ),
          Positioned(
            bottom: size * 0.16,
            child: Container(
              width: size * 0.42,
              height: size * 0.07,
              decoration: BoxDecoration(color: const Color(0xFFFF9933), borderRadius: BorderRadius.circular(size)),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section title used on long screens.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
    child: Row(
      children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
        ?trailing,
      ],
    ),
  );
}

/// Small coloured pill: "12% OFF", "Low stock", "Inactive"…
class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, required this.color, this.filled = false});
  final String text;
  final Color color;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: filled ? color : color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: filled ? Colors.white : color, height: 1.3),
    ),
  );
}
