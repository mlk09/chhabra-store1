import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/i18n.dart';
import '../../core/router.dart';
import '../../core/widgets/common.dart';
import 'welcome_screen.dart';

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

String? _validEmail(BuildContext context, String? v) =>
    _emailRe.hasMatch(v?.trim() ?? '') ? null : context.tr('Enter a valid email', 'सही ईमेल लिखें');

String? _validPassword(BuildContext context, String? v) =>
    (v ?? '').length >= 6 ? null : context.tr('At least 6 characters', 'कम से कम 6 अक्षर');

/// Common layout for the small auth forms.
class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: ListView(padding: const EdgeInsets.all(20), children: children),
        ),
      ),
    ),
  );
}

mixin _Busy<T extends StatefulWidget> on State<T> {
  bool busy = false;

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with _Busy {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hide = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() => run(() async {
    if (!_form.currentState!.validate()) return;
    final notifier = ref.read(sessionProvider.notifier);
    if (ref.read(sessionProvider).value?.isDemo ?? false) await notifier.exitDemo();
    await ref.read(backendProvider).signIn(email: _email.text, password: _password.text);
    await notifier.refresh();
    if (!mounted) return;
    context.go(homeFor(ref.read(sessionProvider).requireValue, ref.read(prefsProvider)));
  });

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: context.tr('Log in', 'लॉग इन'),
      children: [
        const Center(child: AppLogo(size: 64)),
        const SizedBox(height: 24),
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr('Email', 'ईमेल'),
                    prefixIcon: const Icon(Icons.mail_outline),
                  ),
                  validator: (v) => _validEmail(context, v),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: _hide,
                  autofillHints: const [AutofillHints.password],
                  onFieldSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: context.tr('Password', 'पासवर्ड'),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: context.tr('Show password', 'पासवर्ड दिखाएँ'),
                      icon: Icon(_hide ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _hide = !_hide),
                    ),
                  ),
                  validator: (v) => _validPassword(context, v),
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => context.push('/forgot'),
            child: Text(context.tr('Forgot password?', 'पासवर्ड भूल गए?')),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: busy ? null : _login,
          child: busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(context.tr('Log in', 'लॉग इन')),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => context.pushReplacement('/signup'),
          child: Text(context.tr('New here? Create account', 'नए हैं? खाता बनाएँ')),
        ),
        const SizedBox(height: 32),
        Text(
          context.tr('Just looking? Try the demo shop:', 'सिर्फ़ देखना है? डेमो दुकान आज़माएँ:'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        const DemoButtons(),
      ],
    );
  }
}

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> with _Busy {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _signup() => run(() async {
    if (!_form.currentState!.validate()) return;
    final notifier = ref.read(sessionProvider.notifier);
    if (ref.read(sessionProvider).value?.isDemo ?? false) await notifier.exitDemo();
    await ref
        .read(backendProvider)
        .signUp(
          name: _name.text,
          email: _email.text,
          password: _password.text,
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        );
    await notifier.refresh();
    if (!mounted) return;
    showSnack(context, context.tr('Welcome! Your account is ready.', 'स्वागत है! आपका खाता बन गया।'));
    context.go(homeFor(ref.read(sessionProvider).requireValue, ref.read(prefsProvider)));
  });

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: context.tr('Create account', 'खाता बनाएँ'),
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr('Your name', 'आपका नाम'),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (v) =>
                      (v?.trim().length ?? 0) >= 2 ? null : context.tr('Enter your name', 'अपना नाम लिखें'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr('Mobile number (for delivery)', 'मोबाइल नंबर (डिलीवरी के लिए)'),
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                  validator: (v) {
                    final s = (v ?? '').replaceAll(RegExp(r'[\s-]'), '');
                    if (s.isEmpty) return null;
                    return RegExp(r'^\+?[0-9]{10,13}$').hasMatch(s)
                        ? null
                        : context.tr('Enter a 10-digit number', '10 अंकों का नंबर लिखें');
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr('Email', 'ईमेल'),
                    prefixIcon: const Icon(Icons.mail_outline),
                  ),
                  validator: (v) => _validEmail(context, v),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  onFieldSubmitted: (_) => _signup(),
                  decoration: InputDecoration(
                    labelText: context.tr('Create a password', 'पासवर्ड बनाएँ'),
                    prefixIcon: const Icon(Icons.lock_outline),
                    helperText: context.tr('At least 6 characters', 'कम से कम 6 अक्षर'),
                  ),
                  validator: (v) => _validPassword(context, v),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : _signup,
          child: busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
              : Text(context.tr('Create account', 'खाता बनाएँ')),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => context.pushReplacement('/login'),
          child: Text(context.tr('Already have an account? Log in', 'पहले से खाता है? लॉग इन करें')),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr(
            'By signing up you agree to our Terms and Privacy Policy.',
            'साइन अप करके आप हमारी शर्तें और प्राइवेसी पॉलिसी मानते हैं।',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> with _Busy {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: context.tr('Reset password', 'पासवर्ड रीसेट'),
      children: [
        if (_sent)
          MessageView(
            icon: Icons.mark_email_read_outlined,
            title: context.tr('Check your email', 'अपना ईमेल देखें'),
            message: context.tr(
              'We sent a link to set a new password. Open it on this device.',
              'नया पासवर्ड बनाने का लिंक भेजा है। इसे इसी फ़ोन/कंप्यूटर पर खोलें।',
            ),
          )
        else ...[
          Form(
            key: _form,
            child: TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: context.tr('Email', 'ईमेल'),
                prefixIcon: const Icon(Icons.mail_outline),
              ),
              validator: (v) => _validEmail(context, v),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    if (!_form.currentState!.validate()) return;
                    await ref.read(backendProvider).sendPasswordReset(_email.text);
                    if (mounted) setState(() => _sent = true);
                  }),
            child: Text(context.tr('Send reset link', 'रीसेट लिंक भेजें')),
          ),
        ],
      ],
    );
  }
}

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> with _Busy {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: context.tr('Set new password', 'नया पासवर्ड'),
      children: [
        Form(
          key: _form,
          child: TextFormField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: context.tr('New password', 'नया पासवर्ड'),
              prefixIcon: const Icon(Icons.lock_outline),
            ),
            validator: (v) => _validPassword(context, v),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy
              ? null
              : () => run(() async {
                  if (!_form.currentState!.validate()) return;
                  await ref.read(backendProvider).updatePassword(_password.text);
                  await ref.read(sessionProvider.notifier).refresh();
                  if (!context.mounted) return;
                  showSnack(context, context.tr('Password changed.', 'पासवर्ड बदल गया।'));
                  context.go(homeFor(ref.read(sessionProvider).requireValue, ref.read(prefsProvider)));
                }),
          child: Text(context.tr('Save password', 'पासवर्ड सेव करें')),
        ),
      ],
    );
  }
}
