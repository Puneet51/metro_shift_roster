import 'dart:math';
import 'package:flutter/material.dart';
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
  final _otpController = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isAdminMode = false;
  bool _isForgotPinMode = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    _otpController.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  // Generates and auto-fills dummy 6-digit OTP for testing
  void _triggerAutoOtp() {
    final randomOtp = (100000 + Random().nextInt(900000)).toString();
    _otpController.text = randomOtp;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Auto-generated OTP: $randomOtp (Auto-filled)'),
            backgroundColor: const Color(0xFF059669),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    });
  }

  void _startForgotPinFlow() {
    setState(() {
      _isForgotPinMode = true;
      _newPinController.clear();
      _confirmPinController.clear();
    });
    _triggerAutoOtp();
  }

  void _cancelForgotPinFlow() {
    setState(() {
      _isForgotPinMode = false;
      _otpController.clear();
      _newPinController.clear();
      _confirmPinController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    // Auto-generate & fill OTP if user lands on first-time PIN setup
    ref.listen<AuthState>(authNotifierProvider, (previous, next) {
      if (next.status == AuthStatus.needsOtpAndPinSetup &&
          previous?.status != AuthStatus.needsOtpAndPinSetup) {
        _triggerAutoOtp();
      }
    });

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/images/app_logo.png',
                      width: 90,
                      height: 90,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.subway_rounded,
                        size: 80,
                        color: Color(0xFF1E3A8A),
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
                        : 'Operational Duty & Biometric Access Portal',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 28),

                  // 1. ADMIN MODE
                  if (_isAdminMode) ...[
                    TextFormField(
                      controller: _adminEmailController,
                      decoration: const InputDecoration(
                        labelText: 'Admin Email',
                        prefixIcon: Icon(Icons.admin_panel_settings_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Enter admin email' : null,
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
                          v == null || v.isEmpty ? 'Enter password' : null,
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
                              if (_formKey.currentState!.validate()) {
                                ref
                                    .read(authNotifierProvider.notifier)
                                    .loginAdmin(
                                      _adminEmailController.text.trim(),
                                      _adminPasswordController.text.trim(),
                                    );
                              }
                            },
                      child: authState.status == AuthStatus.authenticating
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Login as Administrator',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ]
                  // 2. FORGOT PIN FLOW
                  else if (_isForgotPinMode) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Text(
                        'Reset PIN for ${authState.user?.fullName ?? _phoneController.text}. Verify OTP and create your new 4-digit PIN.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1E3A8A),
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: '6-Digit Verification Code',
                        hintText: 'Auto-filled OTP',
                        prefixIcon: const Icon(Icons.security_rounded),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.autorenew_rounded),
                          tooltip: 'Regenerate OTP',
                          onPressed: _triggerAutoOtp,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.trim().length != 6
                          ? 'Enter 6-digit code'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _newPinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: const InputDecoration(
                        labelText: 'New 4-Digit Security PIN',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.trim().length != 4
                          ? 'PIN must be 4 digits'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _confirmPinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: const InputDecoration(
                        labelText: 'Confirm New 4-Digit PIN',
                        prefixIcon: Icon(Icons.lock_reset_rounded),
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
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: authState.status == AuthStatus.authenticating
                          ? null
                          : () {
                              if (_formKey.currentState!.validate()) {
                                ref
                                    .read(authNotifierProvider.notifier)
                                    .verifyOtpAndSetCustomPin(
                                      otp: _otpController.text.trim(),
                                      newPin: _newPinController.text.trim(),
                                      confirmPin: _confirmPinController.text
                                          .trim(),
                                    )
                                    .then((_) {
                                      if (mounted) {
                                        setState(
                                          () => _isForgotPinMode = false,
                                        );
                                      }
                                    });
                              }
                            },
                      child: authState.status == AuthStatus.authenticating
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Reset PIN & Sign In',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _cancelForgotPinFlow,
                      child: const Text('Back to PIN Login'),
                    ),
                  ]
                  // 3. FIRST-TIME SETUP: CREATE PERSONAL CUSTOM PIN
                  else if (authState.status ==
                      AuthStatus.needsOtpAndPinSetup) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Welcome, ${authState.user?.fullName}! First-time setup: Verify code & create your private 4-digit PIN.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1E3A8A),
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: '6-Digit Verification Code',
                        hintText: 'Auto-filled OTP',
                        prefixIcon: const Icon(Icons.security),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.autorenew_rounded),
                          tooltip: 'Regenerate OTP',
                          onPressed: _triggerAutoOtp,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.trim().length != 6
                          ? 'Enter 6-digit code'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _newPinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: const InputDecoration(
                        labelText: 'Create Your 4-Digit Security PIN',
                        prefixIcon: Icon(Icons.lock_outline),
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) => v == null || v.trim().length != 4
                          ? 'PIN must be 4 digits'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _confirmPinController,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: const InputDecoration(
                        labelText: 'Confirm Your 4-Digit PIN',
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
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: authState.status == AuthStatus.authenticating
                          ? null
                          : () {
                              if (_formKey.currentState!.validate()) {
                                ref
                                    .read(authNotifierProvider.notifier)
                                    .verifyOtpAndSetCustomPin(
                                      otp: _otpController.text.trim(),
                                      newPin: _newPinController.text.trim(),
                                      confirmPin: _confirmPinController.text
                                          .trim(),
                                    );
                              }
                            },
                      child: authState.status == AuthStatus.authenticating
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Set PIN & Sign In',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                    TextButton(
                      onPressed: () => ref
                          .read(authNotifierProvider.notifier)
                          .resetToPhoneInput(),
                      child: const Text('Use a different mobile number'),
                    ),
                  ]
                  // 4. RETURNING USER: ENTER EXISTING CUSTOM PIN
                  else if (authState.status == AuthStatus.pinRequired) ...[
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
                      maxLength: 4,
                      decoration: const InputDecoration(
                        labelText: 'Your 4-Digit Security PIN',
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
                        onPressed: _startForgotPinFlow,
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
                              if (_formKey.currentState!.validate()) {
                                ref
                                    .read(authNotifierProvider.notifier)
                                    .loginWithPin(_pinController.text.trim());
                              }
                            },
                      child: authState.status == AuthStatus.authenticating
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Login to Portal',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                    TextButton(
                      onPressed: () => ref
                          .read(authNotifierProvider.notifier)
                          .resetToPhoneInput(),
                      child: const Text('Use a different mobile number'),
                    ),
                  ]
                  // 5. ENTER PHONE NUMBER
                  else ...[
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
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
                              if (_formKey.currentState!.validate()) {
                                ref
                                    .read(authNotifierProvider.notifier)
                                    .checkPhone(_phoneController.text.trim());
                              }
                            },
                      child: authState.status == AuthStatus.authenticating
                          ? const CircularProgressIndicator(color: Colors.white)
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
                        _isForgotPinMode = false;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
