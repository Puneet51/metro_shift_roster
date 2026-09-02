import 'package:flutter/material.dart';
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
  late final TextEditingController _bioController;
  late final TextEditingController _companyController;
  late final TextEditingController _bmrclController;

  @override
  void initState() {
    super.initState();
    final op = widget.operator;
    _nameController = TextEditingController(text: op?.fullName ?? '');
    _phoneController = TextEditingController(text: op?.phoneNumber ?? '');
    _bioController = TextEditingController(text: op?.biometricId ?? '');
    _companyController = TextEditingController(text: op?.companyId ?? '');
    _bmrclController = TextEditingController(text: op?.bmrclId ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _companyController.dispose();
    _bmrclController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.operator != null;
    final actionState = ref.watch(staffActionNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Operator' : 'Add Operator')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: 'Full Name', border: OutlineInputBorder()),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                    labelText: 'Phone Number', border: OutlineInputBorder()),
                validator: (v) => v == null || v.trim().length < 10
                    ? 'Valid 10-digit phone required'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bmrclController,
                decoration: const InputDecoration(
                    labelText: 'BMRCL ID (Optional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _companyController,
                decoration: const InputDecoration(
                    labelText: 'Company ID (Optional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bioController,
                decoration: const InputDecoration(
                    labelText: 'Biometric ID (Optional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: actionState.isLoading
                    ? null
                    : () async {
                        if (!_formKey.currentState!.validate()) return;
                        if (isEditing) {
                          await ref
                              .read(staffActionNotifierProvider.notifier)
                              .updateOperator(
                                operatorId: widget.operator!.id,
                                fullName: _nameController.text,
                                phoneNumber: _phoneController.text,
                                biometricId: _bioController.text,
                                companyId: _companyController.text,
                                bmrclId: _bmrclController.text,
                              );
                        } else {
                          await ref
                              .read(staffActionNotifierProvider.notifier)
                              .addOperator(
                                _nameController.text,
                                _phoneController.text,
                              );
                        }
                        if (mounted) Navigator.pop(context);
                      },
                child: actionState.isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(isEditing ? 'Save Changes' : 'Register Operator'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
