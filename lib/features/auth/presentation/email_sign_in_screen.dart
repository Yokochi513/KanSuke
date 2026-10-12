import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_state.dart';

/// NFR-4: Firebase Authentication のメール認証でログイン・新規登録する。
class EmailSignInScreen extends ConsumerStatefulWidget {
  const EmailSignInScreen({super.key});

  @override
  ConsumerState<EmailSignInScreen> createState() => _EmailSignInScreenState();
}

class _EmailSignInScreenState extends ConsumerState<EmailSignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirmation = TextEditingController();
  bool _obscurePassword = true;
  bool _isSignUp = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordConfirmation.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (ref.read(authActionControllerProvider).isLoading ||
        !_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    final actions = ref.read(authActionControllerProvider.notifier);
    if (_isSignUp) {
      await actions.signUpWithEmailAndPassword(
        _email.text.trim(),
        _password.text,
      );
    } else {
      await actions.signInWithEmailAndPassword(
        _email.text.trim(),
        _password.text,
      );
    }
    if (!mounted) return;
    if (ref.read(authActionControllerProvider).errorMessage == null &&
        ModalRoute.of(context)?.isCurrent == true) {
      TextInput.finishAutofillContext();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authActionControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_isSignUp ? 'アカウントを作成' : 'メールアドレスでログイン')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _email,
                        enabled: !state.isLoading,
                        decoration: const InputDecoration(labelText: 'メールアドレス'),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [
                          AutofillHints.username,
                          AutofillHints.email,
                        ],
                        autocorrect: false,
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) return 'メールアドレスを入力してください。';
                          if (!RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(email)) {
                            return 'メールアドレスの形式を確認してください。';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        enabled: !state.isLoading,
                        obscureText: _obscurePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: [
                          _isSignUp
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        textInputAction: _isSignUp
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onFieldSubmitted: _isSignUp ? null : (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'パスワード',
                          helperText: _isSignUp ? '6文字以上で入力してください' : null,
                          suffixIcon: IconButton(
                            tooltip: _obscurePassword ? 'パスワードを表示' : 'パスワードを隠す',
                            onPressed: state.isLoading
                                ? null
                                : () => setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  }),
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'パスワードを入力してください。';
                          }
                          if (_isSignUp && value.length < 6) {
                            return 'パスワードは6文字以上で入力してください。';
                          }
                          return null;
                        },
                      ),
                      if (_isSignUp) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordConfirmation,
                          enabled: !state.isLoading,
                          obscureText: _obscurePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.newPassword],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'パスワード（確認）',
                          ),
                          validator: (value) =>
                              value != _password.text ? 'パスワードが一致しません。' : null,
                        ),
                      ],
                      const SizedBox(height: 24),
                      if (state.errorMessage != null) ...[
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            state.errorMessage!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      FilledButton(
                        onPressed: state.isLoading ? null : _submit,
                        child: Text(_isSignUp ? '登録する' : 'ログイン'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: state.isLoading
                            ? null
                            : () {
                                ref
                                    .read(authActionControllerProvider.notifier)
                                    .clearError();
                                _formKey.currentState!.reset();
                                _password.clear();
                                _passwordConfirmation.clear();
                                setState(() {
                                  _isSignUp = !_isSignUp;
                                  _obscurePassword = true;
                                });
                              },
                        child: Text(
                          _isSignUp ? '既にアカウントをお持ちの方はログイン' : 'アカウントを作成',
                        ),
                      ),
                      if (state.isLoading) ...[
                        const SizedBox(height: 16),
                        const Center(child: CircularProgressIndicator()),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
