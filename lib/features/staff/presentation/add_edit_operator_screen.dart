import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/operator_model.dart';
import 'staff_provider.dart';

class AddEditOperatorScreen extends ConsumerStatefulWidget {
  final OperatorModel? operator;
  const AddEditOperatorScreen({super.key, this.operator});

  @override
  ConsumerState<AddEditOperatorScreen> createState() =>
      _AddEditOperatorScreenState();
}

class _AddEditOperatorScreenState extends ConsumerState<AddEditOperatorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _fatherNameController;
  late final TextEditingController _empCodeController;
  late final TextEditingController _bioController;
  late final TextEditingController _bmrclController;
  late final TextEditingController _esiController;
  late final TextEditingController _uanController;
  late final TextEditingController _dojController;

  @override
  void initState() {
    super.initState();
    final op = widget.operator;
    _nameController = TextEditingController(text: op?.fullName ?? '');
    _phoneController = TextEditingController(text: op?.phoneNumber ?? '');
    _fatherNameController = TextEditingController(text: op?.fatherName ?? '');
    _empCodeController = TextEditingController(text: op?.empCode ?? '');
    _bioController = TextEditingController(text: op?.biometricId ?? '');
    _bmrclController = TextEditingController(text: op?.bmrclId ?? '');
    _esiController = TextEditingController(text: op?.esiNo ?? '');
    _uanController = TextEditingController(text: op?.uanNo ?? '');
    _dojController = TextEditingController(text: op?.doj ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _fatherNameController.dispose();
    _empCodeController.dispose();
    _bioController.dispose();
    _bmrclController.dispose();
    _esiController.dispose();
    _uanController.dispose();
    _dojController.dispose();
    super.dispose();
  }

  Future<void> _selectDateOfJoining() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_dojController.text.trim()) ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _dojController.text =
            "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
      });
    }
  }

  String? _nullIfEmpty(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.operator != null;
    final actionState = ref.watch(staffActionNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Operator' : 'Add Operator'),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Personal Identity',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF1E3A8A),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(
                  labelText: 'Phone Number (10 Digits) *',
                  prefixText: '+91 ',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_android_outlined),
                ),
                validator: (v) => v == null || v.trim().length != 10
                    ? 'Valid 10-digit phone required'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _fatherNameController,
                decoration: const InputDecoration(
                  labelText: "Father's Name (Optional)",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.family_restroom_outlined),
                ),
              ),
              const SizedBox(height: 20),

              const Text(
                'Muster Roll & Statutory Details',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF1E3A8A),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _empCodeController,
                      decoration: const InputDecoration(
                        labelText: 'Emp Code',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _bioController,
                      decoration: const InputDecoration(
                        labelText: 'Biometric ID',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.fingerprint_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _bmrclController,
                decoration: const InputDecoration(
                  labelText: 'BMRCL ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.subway_outlined),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _esiController,
                      decoration: const InputDecoration(
                        labelText: 'ESI Number',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.health_and_safety_outlined),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _uanController,
                      decoration: const InputDecoration(
                        labelText: 'UAN Number',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _dojController,
                readOnly: true,
                onTap: _selectDateOfJoining,
                decoration: const InputDecoration(
                  labelText: 'Date of Joining (DOJ)',
                  hintText: 'YYYY-MM-DD',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
              ),
              const SizedBox(height: 26),

              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A8A),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: actionState.isLoading
                    ? null
                    : () async {
                        if (!_formKey.currentState!.validate()) return;
                        if (isEditing) {
                          try {
                            await ref
                                .read(staffActionNotifierProvider.notifier)
                                .updateOperator(
                                  operatorId: widget.operator!.id,
                                  fullName: _nameController.text.trim(),
                                  phoneNumber: _phoneController.text.trim(),
                                  biometricId: _nullIfEmpty(
                                    _bioController.text,
                                  ),
                                  empCode: _nullIfEmpty(
                                    _empCodeController.text,
                                  ),
                                  bmrclId: _nullIfEmpty(_bmrclController.text),
                                  fatherName: _nullIfEmpty(
                                    _fatherNameController.text,
                                  ),
                                  esiNo: _nullIfEmpty(_esiController.text),
                                  uanNo: _nullIfEmpty(_uanController.text),
                                  doj: _nullIfEmpty(_dojController.text),
                                );

                            // Invalidate cache to force list refetch
                            ref.invalidate(staffListProvider);

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Operator updated successfully.',
                                  ),
                                  backgroundColor: Color(0xFF059669),
                                ),
                              );
                              Navigator.pop(context);
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Update failed: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        } else {
                          try {
                            await ref
                                .read(staffActionNotifierProvider.notifier)
                                .addOperator(
                                  fullName: _nameController.text.trim(),
                                  phoneNumber: _phoneController.text.trim(),
                                  biometricId: _nullIfEmpty(
                                    _bioController.text,
                                  ),
                                  empCode: _nullIfEmpty(
                                    _empCodeController.text,
                                  ),
                                  bmrclId: _nullIfEmpty(_bmrclController.text),
                                  fatherName: _nullIfEmpty(
                                    _fatherNameController.text,
                                  ),
                                  esiNo: _nullIfEmpty(_esiController.text),
                                  uanNo: _nullIfEmpty(_uanController.text),
                                  doj: _nullIfEmpty(_dojController.text),
                                );

                            // Invalidate cache to force list refetch
                            ref.invalidate(staffListProvider);

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '${_nameController.text.trim()} registered successfully.',
                                  ),
                                  backgroundColor: const Color(0xFF059669),
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                              Navigator.pop(context);
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Registration failed: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        }
                      },
                child: actionState.isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        isEditing ? 'Save Changes' : 'Register Operator',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
