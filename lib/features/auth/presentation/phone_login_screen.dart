import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';

class PhoneLoginScreen extends ConsumerStatefulWidget {
  const PhoneLoginScreen({super.key});

  @override
  ConsumerState<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends ConsumerState<PhoneLoginScreen> {
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminPasswordController = TextEditingController();

  final _phoneFormKey = GlobalKey<FormState>();
  final _pinFormKey = GlobalKey<FormState>();
  final _setupPinFormKey = GlobalKey<FormState>();
  final _adminFormKey = GlobalKey<FormState>();

  bool _isAdminMode = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  void _showSupervisorAssistanceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: Color(0xFF1E3A8A)),
            SizedBox(width: 8),
            Text(
              'PIN Reset Assistance',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          'For security reasons, operators cannot self-reset login credentials.\n\n'
          'Please contact your assigned Station Supervisor. Your supervisor can reset your PIN from their management panel, allowing you to create a fresh 4-digit PIN.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Understood', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/metro_logo.png',
                      width: 85,
                      height: 85,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(
                        Icons.subway_rounded,
                        size: 80,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _isAdminMode
                      ? 'Metro Shift Roster Admin'
                      : 'Metro Shift Roster',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isAdminMode
                      ? 'Central Organization & Multi-Supervisor Management'
                      : 'Operational Duty & Native Biometric Access Portal',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 28),

                // -------------------------------------------------------------
                // 1. ADMIN MODE
                // -------------------------------------------------------------
                if (_isAdminMode) ...[
                  Form(
                    key: _adminFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _adminEmailController,
                          decoration: const InputDecoration(
                            labelText: 'Admin Email',
                            prefixIcon: Icon(Icons.admin_panel_settings_rounded),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Enter admin email' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _adminPasswordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Admin Password',
                            prefixIcon: Icon(Icons.lock_rounded),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) =>
                              v == null || v.trim().isEmpty ? 'Enter password' : null,
                        ),
                        const SizedBox(height: 18),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A8A),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: authState.status == AuthStatus.authenticating
                              ? null
                              : () {
                                  if (_adminFormKey.currentState!.validate()) {
                                    ref
                                        .read(authNotifierProvider.notifier)
                                        .loginAdmin(
                                          _adminEmailController.text.trim(),
                                          _adminPasswordController.text.trim(),
                                        );
                                  }
                                },
                          child: authState.status == AuthStatus.authenticating
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text(
                                  'Login as Administrator',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ]

                // -------------------------------------------------------------
                // 2. FIRST-TIME OR RESET: CREATE 4-DIGIT PIN
                // -------------------------------------------------------------
                else if (authState.status == AuthStatus.needsPinSetup) ...[
                  Form(
                    key: _setupPinFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Text(
                            'Welcome, ${authState.user?.fullName ?? "Staff"}!\nSetup Required: Create your permanent 4-digit PIN for future logins.',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF1E3A8A),
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: _newPinController,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Create 4-Digit PIN',
                            prefixIcon: Icon(Icons.lock_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => v == null || v.trim().length != 4
                              ? 'PIN must be exactly 4 digits'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmPinController,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Confirm 4-Digit PIN',
                            prefixIcon: Icon(Icons.lock_reset),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().length != 4) {
                              return 'Confirm 4-digit PIN';
                            }
                            if (v != _newPinController.text) {
                              return 'PINs do not match';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 18),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: authState.status == AuthStatus.authenticating
                              ? null
                              : () {
                                  if (_setupPinFormKey.currentState!.validate()) {
                                    ref
                                        .read(authNotifierProvider.notifier)
                                        .setCustomPin(
                                          newPin: _newPinController.text.trim(),
                                          confirmPin: _confirmPinController.text.trim(),
                                        );
                                  }
                                },
                          child: authState.status == AuthStatus.authenticating
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text(
                                  'Save PIN & Enter Portal',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            _newPinController.clear();
                            _confirmPinController.clear();
                            ref.read(authNotifierProvider.notifier).resetToPhoneInput();
                          },
                          child: const Text('Cancel & Use Different Number'),
                        ),
                      ],
                    ),
                  ),
                ]

                // -------------------------------------------------------------
                // 3. RETURNING USER: ENTER 4-DIGIT PIN
                // -------------------------------------------------------------
                else if (authState.status == AuthStatus.pinRequired) ...[
                  Form(
                    key: _pinFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Welcome back, ${authState.user?.fullName ?? "Staff"}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _pinController,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Security PIN',
                            hintText: 'Enter your 4-digit PIN',
                            prefixIcon: Icon(Icons.lock),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().length != 4) {
                              return 'Enter your 4-digit PIN';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _showSupervisorAssistanceDialog,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(50, 30),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Forgot PIN?',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A8A),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: authState.status == AuthStatus.authenticating
                              ? null
                              : () {
                                  if (_pinFormKey.currentState!.validate()) {
                                    ref
                                        .read(authNotifierProvider.notifier)
                                        .loginWithPin(_pinController.text.trim());
                                  }
                                },
                          child: authState.status == AuthStatus.authenticating
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text(
                                  'Login to Portal',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () {
                            _pinController.clear();
                            ref.read(authNotifierProvider.notifier).resetToPhoneInput();
                          },
                          child: const Text('Use a different mobile number'),
                        ),
                      ],
                    ),
                  ),
                ]

                // -------------------------------------------------------------
                // 4. ENTER PHONE NUMBER (DEFAULT STEP)
                // -------------------------------------------------------------
                else ...[
                  Form(
                    key: _phoneFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(10),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Registered Mobile Number',
                            prefixText: '+91 ',
                            prefixIcon: Icon(Icons.phone_android),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().length != 10) {
                              return 'Enter valid 10-digit mobile number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A8A),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: authState.status == AuthStatus.authenticating
                              ? null
                              : () {
                                  if (_phoneFormKey.currentState!.validate()) {
                                    ref
                                        .read(authNotifierProvider.notifier)
                                        .checkPhone(_phoneController.text.trim());
                                  }
                                },
                          child: authState.status == AuthStatus.authenticating
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                )
                              : const Text(
                                  'Continue',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (authState.errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    authState.errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 13,
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                TextButton.icon(
                  icon: Icon(
                    _isAdminMode
                        ? Icons.phone_iphone_rounded
                        : Icons.admin_panel_settings_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _isAdminMode
                        ? 'Switch to Staff / Supervisor Login'
                        : 'Admin Master Portal Login',
                  ),
                  onPressed: () {
                    setState(() {
                      _isAdminMode = !_isAdminMode;
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}