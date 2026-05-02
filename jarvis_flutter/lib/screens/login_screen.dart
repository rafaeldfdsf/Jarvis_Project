import 'package:flutter/material.dart';

import '../services/auth_service.dart';

enum _AuthMode { login, register, verifyEmail, forgotPassword, resetPassword }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _auth = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _verificationCodeController =
      TextEditingController();
  final TextEditingController _resetCodeController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  _AuthMode _mode = _AuthMode.login;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    _verificationCodeController.dispose();
    _resetCodeController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final displayName = _displayNameController.text.trim();
    final verificationCode = _verificationCodeController.text.trim();
    final resetCode = _resetCodeController.text.trim();
    final newPassword = _newPasswordController.text;

    if (email.isEmpty) {
      _showMessage('Preenche o email.');
      return;
    }

    switch (_mode) {
      case _AuthMode.login:
        if (password.isEmpty) {
          _showMessage('Preenche a palavra-passe.');
          return;
        }
        await _auth.login(email: email, password: password);
        break;
      case _AuthMode.register:
        if (password.isEmpty) {
          _showMessage('Preenche a palavra-passe.');
          return;
        }
        final success = await _auth.register(
          email: email,
          password: password,
          displayName: displayName,
        );
        if (success && mounted) {
          setState(() {
            _mode = _AuthMode.verifyEmail;
          });
        }
        break;
      case _AuthMode.verifyEmail:
        if (verificationCode.isEmpty) {
          _showMessage('Preenche o codigo enviado por email.');
          return;
        }
        await _auth.verifyEmail(email: email, code: verificationCode);
        break;
      case _AuthMode.forgotPassword:
        final success = await _auth.requestPasswordReset(email: email);
        if (success && mounted) {
          setState(() {
            _mode = _AuthMode.resetPassword;
          });
        }
        break;
      case _AuthMode.resetPassword:
        if (resetCode.isEmpty || newPassword.isEmpty) {
          _showMessage('Preenche o codigo e a nova palavra-passe.');
          return;
        }
        final success = await _auth.resetPassword(
          email: email,
          code: resetCode,
          newPassword: newPassword,
        );
        if (success && mounted) {
          setState(() {
            _mode = _AuthMode.login;
            _passwordController.clear();
            _newPasswordController.clear();
            _resetCodeController.clear();
          });
        }
        break;
    }
  }

  Future<void> _resendVerification() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('Preenche o email.');
      return;
    }
    await _auth.resendVerification(email: email);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String get _title {
    switch (_mode) {
      case _AuthMode.login:
        return 'Entrar';
      case _AuthMode.register:
        return 'Criar Conta';
      case _AuthMode.verifyEmail:
        return 'Confirmar Email';
      case _AuthMode.forgotPassword:
        return 'Recuperar Palavra-passe';
      case _AuthMode.resetPassword:
        return 'Nova Palavra-passe';
    }
  }

  String get _subtitle {
    switch (_mode) {
      case _AuthMode.login:
        return 'Entra para carregares as tuas configuracoes e sessoes.';
      case _AuthMode.register:
        return 'Cria uma conta para sincronizares configuracoes entre computadores.';
      case _AuthMode.verifyEmail:
        return 'Introduz o codigo que foi enviado para o teu email.';
      case _AuthMode.forgotPassword:
        return 'Enviamos um codigo por email para definires uma nova palavra-passe.';
      case _AuthMode.resetPassword:
        return 'Usa o codigo recebido por email e escolhe uma nova palavra-passe.';
    }
  }

  String get _submitLabel {
    if (_auth.loading) {
      return 'A processar...';
    }
    switch (_mode) {
      case _AuthMode.login:
        return 'Entrar';
      case _AuthMode.register:
        return 'Criar conta';
      case _AuthMode.verifyEmail:
        return 'Confirmar email';
      case _AuthMode.forgotPassword:
        return 'Enviar codigo';
      case _AuthMode.resetPassword:
        return 'Guardar nova palavra-passe';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _auth,
      builder: (context, _) {
        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF040A11), Color(0xFF0A1622), Color(0xFF03070D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xCC07111B),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: const Color(0xFF17324C)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _subtitle,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.72),
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 22),
                        if (_mode == _AuthMode.register) ...[
                          _AuthField(
                            controller: _displayNameController,
                            label: 'Nome a mostrar',
                            icon: Icons.badge_outlined,
                            hintText: 'Rafael',
                          ),
                          const SizedBox(height: 14),
                        ],
                        _AuthField(
                          controller: _emailController,
                          label: 'Email',
                          icon: Icons.mail_outline_rounded,
                          hintText: 'tu@exemplo.com',
                          keyboardType: TextInputType.emailAddress,
                        ),
                        if (_mode == _AuthMode.login || _mode == _AuthMode.register) ...[
                          const SizedBox(height: 14),
                          _AuthField(
                            controller: _passwordController,
                            label: 'Palavra-passe',
                            icon: Icons.lock_outline_rounded,
                            hintText: '********',
                            obscureText: true,
                          ),
                        ],
                        if (_mode == _AuthMode.verifyEmail) ...[
                          const SizedBox(height: 14),
                          _AuthField(
                            controller: _verificationCodeController,
                            label: 'Codigo de verificacao',
                            icon: Icons.mark_email_read_outlined,
                            hintText: '123456',
                            keyboardType: TextInputType.number,
                          ),
                        ],
                        if (_mode == _AuthMode.resetPassword) ...[
                          const SizedBox(height: 14),
                          _AuthField(
                            controller: _resetCodeController,
                            label: 'Codigo de recuperacao',
                            icon: Icons.password_rounded,
                            hintText: '123456',
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 14),
                          _AuthField(
                            controller: _newPasswordController,
                            label: 'Nova palavra-passe',
                            icon: Icons.lock_reset_rounded,
                            hintText: '********',
                            obscureText: true,
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _auth.loading ? null : _submit,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              child: Text(_submitLabel),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildActions(),
                        if ((_auth.notice ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            _auth.notice!,
                            style: const TextStyle(
                              color: Color(0xFF8BE9C1),
                              height: 1.4,
                            ),
                          ),
                        ],
                        if ((_auth.error ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            _auth.error!,
                            style: const TextStyle(
                              color: Color(0xFFFFB4A8),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActions() {
    switch (_mode) {
      case _AuthMode.login:
        return Column(
          children: [
            Center(
              child: TextButton(
                onPressed: _auth.loading
                    ? null
                    : () {
                        setState(() {
                          _mode = _AuthMode.register;
                        });
                      },
                child: const Text('Criar uma conta nova'),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: _auth.loading
                    ? null
                    : () {
                        setState(() {
                          _mode = _AuthMode.verifyEmail;
                        });
                      },
                child: const Text('Ja tenho um codigo de verificacao'),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: _auth.loading
                    ? null
                    : () {
                        setState(() {
                          _mode = _AuthMode.forgotPassword;
                        });
                      },
                child: const Text('Esqueci-me da palavra-passe'),
              ),
            ),
          ],
        );
      case _AuthMode.register:
        return Center(
          child: TextButton(
            onPressed: _auth.loading
                ? null
                : () {
                    setState(() {
                      _mode = _AuthMode.login;
                    });
                  },
            child: const Text('Ja tenho conta'),
          ),
        );
      case _AuthMode.verifyEmail:
        return Column(
          children: [
            Center(
              child: TextButton(
                onPressed: _auth.loading ? null : _resendVerification,
                child: const Text('Reenviar codigo'),
              ),
            ),
            Center(
              child: TextButton(
                onPressed: _auth.loading
                    ? null
                    : () {
                        setState(() {
                          _mode = _AuthMode.login;
                        });
                      },
                child: const Text('Voltar ao login'),
              ),
            ),
          ],
        );
      case _AuthMode.forgotPassword:
        return Center(
          child: TextButton(
            onPressed: _auth.loading
                ? null
                : () {
                    setState(() {
                      _mode = _AuthMode.login;
                    });
                  },
            child: const Text('Voltar ao login'),
          ),
        );
      case _AuthMode.resetPassword:
        return Center(
          child: TextButton(
            onPressed: _auth.loading
                ? null
                : () {
                    setState(() {
                      _mode = _AuthMode.login;
                    });
                  },
            child: const Text('Voltar ao login'),
          ),
        );
    }
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.hintText,
    this.keyboardType,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String hintText;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon),
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.82)),
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.36)),
        filled: true,
        fillColor: Colors.white.withOpacity(0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}
