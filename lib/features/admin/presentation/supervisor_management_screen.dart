import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/admin/data/admin_repository.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(SupabaseService.client);
});

final supervisorsListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      final repo = ref.watch(adminRepositoryProvider);
      final currentUser = ref.watch(authNotifierProvider).user;
      return repo.getSupervisors(currentUser?.orgId ?? '');
    });

final centralAdminMetricsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      final res = await SupabaseService.client.rpc('get_central_admin_metrics');
      return (res as Map<String, dynamic>?) ?? {};
    });

class SupervisorManagementScreen extends ConsumerStatefulWidget {
  const SupervisorManagementScreen({super.key});

  @override
  ConsumerState<SupervisorManagementScreen> createState() =>
      _SupervisorManagementScreenState();
}

class _SupervisorManagementScreenState
    extends ConsumerState<SupervisorManagementScreen> {
  bool _isProcessing = false;

  void _showPinDialog({
    required String title,
    required String recipientName,
    required String pin,
    required String description,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.vpn_key_rounded, color: Color(0xFF059669)),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Temporary 4-Digit Login PIN for $recipientName:'),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF3B82F6),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText(
                      pin,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.copy_rounded,
                        color: Color(0xFF1E3A8A),
                      ),
                      tooltip: 'Copy PIN',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: pin));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('PIN copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              description,
              style: const TextStyle(fontSize: 12.5, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showAddRelieverDialog(Map<String, dynamic> supervisor) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    bool isDialogLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.person_add_alt_1_rounded,
                color: Color(0xFF7C3AED),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Add Reliever for ${supervisor['full_name']}',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Reliever Name *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter reliever name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Phone Number (10 Digits) *',
                      prefixText: '+91 ',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone_android),
                    ),
                    validator: (v) => v == null || v.trim().length != 10
                        ? 'Enter valid 10-digit number'
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isDialogLoading
                  ? null
                  : () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
              ),
              onPressed: isDialogLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => isDialogLoading = true);
                      try {
                        await ref
                            .read(adminRepositoryProvider)
                            .addSupervisorReliever(
                              supervisorId: supervisor['id'].toString(),
                              fullName: nameController.text.trim(),
                              phoneNumber: phoneController.text.trim(),
                            );

                        if (mounted) {
                          Navigator.of(dialogCtx).pop();
                          ref.invalidate(supervisorsListProvider);
                          ref.invalidate(centralAdminMetricsProvider);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${nameController.text.trim()} was created. They will set their own PIN on first login.',
                              ),
                              backgroundColor: const Color(0xFF059669),
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isDialogLoading = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Failed: ${e.toString().replaceAll('Exception: ', '')}',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: isDialogLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Add Reliever',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddSupervisorDialog() {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    bool isDialogLoading = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.person_add_rounded, color: Color(0xFF1E3A8A)),
              SizedBox(width: 8),
              Text(
                'Register Supervisor',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter full name'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Phone Number (10 Digits) *',
                      prefixText: '+91 ',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.phone_android),
                    ),
                    validator: (v) => v == null || v.trim().length != 10
                        ? 'Enter valid 10-digit number'
                        : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isDialogLoading
                  ? null
                  : () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
              ),
              onPressed: isDialogLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => isDialogLoading = true);
                      try {
                        final currentAdmin = ref
                            .read(authNotifierProvider)
                            .user;
                        await ref
                            .read(adminRepositoryProvider)
                            .addSupervisor(
                              orgId: currentAdmin?.orgId ?? '',
                              fullName: nameController.text.trim(),
                              phoneNumber: phoneController.text.trim(),
                            );
                        if (mounted) {
                          Navigator.of(dialogCtx).pop();
                          ref.invalidate(supervisorsListProvider);
                          ref.invalidate(centralAdminMetricsProvider);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${nameController.text.trim()} was created. They will set their own PIN on first login.',
                              ),
                              backgroundColor: const Color(0xFF059669),
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isDialogLoading = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Failed: ${e.toString().replaceAll('Exception: ', '')}',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
              child: isDialogLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Create Supervisor',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleGeneratePin(Map<String, dynamic> supervisor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: Color(0xFFB45309)),
            SizedBox(width: 8),
            Text(
              'Reset Supervisor PIN',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Generate a new temporary 4-digit login PIN for ${supervisor['full_name']}?',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Generate PIN',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);
    try {
      final currentAdmin = ref.read(authNotifierProvider).user;
      final tempPin = await ref
          .read(adminRepositoryProvider)
          .adminGenerateAndSendSupervisorPin(
            supervisorId: supervisor['id'].toString(),
            adminId: currentAdmin!.id,
          );
      if (mounted) {
        _showPinDialog(
          title: 'Supervisor PIN Reset',
          recipientName: supervisor['full_name'] ?? 'Supervisor',
          pin: tempPin,
          description:
              'This temporary 4-digit PIN has been generated. Share this PIN directly with the supervisor.',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to reset PIN: ${e.toString().replaceAll('Exception: ', '')}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleDeleteReliever(Map<String, dynamic> reliever) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Deletion', style: TextStyle(color: Colors.red)),
        content: Text('Are you sure you want to delete reliever ${reliever['full_name']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isProcessing = true);
    try {
      final currentAdmin = ref.read(authNotifierProvider).user;
      await ref.read(adminRepositoryProvider).deleteSupervisor(
        supervisorId: reliever['id'].toString(),
        adminId: currentAdmin!.id,
      );
      if (mounted) {
        ref.invalidate(supervisorsListProvider);
        ref.invalidate(centralAdminMetricsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reliever deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: ${e.toString().replaceAll('Exception: ', '')}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleDeleteSupervisor(Map<String, dynamic> supervisor) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Confirm Deletion',
          style: TextStyle(color: Colors.red),
        ),
        content: Text(
          'Are you sure you want to deactivate supervisor ${supervisor['full_name']}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isProcessing = true);
    try {
      final currentAdmin = ref.read(authNotifierProvider).user;
      await ref
          .read(adminRepositoryProvider)
          .deleteSupervisor(
            supervisorId: supervisor['id'].toString(),
            adminId: currentAdmin!.id,
          );
      if (mounted) {
        ref.invalidate(supervisorsListProvider);
        ref.invalidate(centralAdminMetricsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supervisor deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to delete: ${e.toString().replaceAll('Exception: ', '')}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Widget _countChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF475569)),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supervisorsAsync = ref.watch(supervisorsListProvider);
    final metricsAsync = ref.watch(centralAdminMetricsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Metro Shift Roster — Central Admin Portal',
          style: TextStyle(fontSize: 16),
        ),
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1E3A8A),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Supervisor',
          style: TextStyle(color: Colors.white),
        ),
        onPressed: _showAddSupervisorDialog,
      ),
      body: RefreshIndicator(
        color: const Color(0xFF1E3A8A),
        onRefresh: () async {
          ref.invalidate(supervisorsListProvider);
          ref.invalidate(centralAdminMetricsProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Supervisors: ${supervisorsAsync.value?.length ?? 0}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    metricsAsync.when(
                      data: (m) => Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E3A8A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.subway_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${m['stations'] ?? 0} Stations',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.people_alt_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${m['staff'] ?? 0} Staff',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      loading: () => const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      error: (_, __) => const SizedBox(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              supervisorsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF1E3A8A)),
                  ),
                ),
                error: (err, _) => Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Error: $err',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
                data: (supervisors) {
                  if (supervisors.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(
                        child: Text(
                          'No supervisors registered yet.\nTap "Add Supervisor" to register one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 14),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: supervisors.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final sup = supervisors[index];
                      final bool isActive = sup['is_active'] ?? true;
                      final int opCount = (sup['staff_count'] ?? sup['total_operators'] ?? 0) as int;
                      final int stationCount = (sup['station_count'] ?? 0) as int;

                      // Per-supervisor resource counts.
                      // These counts are scoped to this supervisor only.
                      final countsRow = Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
                        child: Row(
                          children: [
                            _countChip(Icons.location_on_outlined, '$stationCount Stations'),
                            const SizedBox(width: 8),
                            _countChip(Icons.groups_outlined, '$opCount Staff'),
                          ],
                        ),
                      );

                      // Extract relievers
                      final rawRelievers = sup['relievers'];
                      final List<Map<String, dynamic>> relieversList = [];

                      if (rawRelievers is List) {
                        for (final item in rawRelievers) {
                          if (item is Map) {
                            relieversList.add(Map<String, dynamic>.from(item));
                          }
                        }
                      } else if (rawRelievers is String &&
                          rawRelievers.trim().isNotEmpty) {
                        try {
                          final decoded = jsonDecode(rawRelievers);
                          if (decoded is List) {
                            for (final item in decoded) {
                              if (item is Map) {
                                relieversList.add(
                                  Map<String, dynamic>.from(item),
                                );
                              }
                            }
                          }
                        } catch (_) {}
                      }

                      return Card(
                        key: ValueKey(
                          'sup_card_${sup['id']}_${relieversList.length}',
                        ),
                        elevation: 1.5,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            countsRow,
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: const Color(0xFF1E3A8A),
                                    child: Text(
                                      (sup['full_name'] ?? 'S')[0]
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          sup['full_name'] ?? 'Supervisor',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '+91 ${sup['phone_number'] ?? ""}',
                                          style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: const Color(0xFFBFDBFE),
                                      ),
                                    ),
                                    child: Text(
                                      '$opCount Staff',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1E3A8A),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Switch(
                                    value: isActive,
                                    activeColor: const Color(0xFF059669),
                                    onChanged: (val) async {
                                      await ref
                                          .read(adminRepositoryProvider)
                                          .updateSupervisor(
                                            supervisorId: sup['id'],
                                            fullName: sup['full_name'],
                                            phoneNumber: sup['phone_number'],
                                            isActive: val,
                                          );
                                      ref.invalidate(supervisorsListProvider);
                                    },
                                  ),
                                ],
                              ),

                              
                              Container(
                                margin: const EdgeInsets.only(top: 10),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Colors.amber.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: Colors.amber,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Relievers detected: ${relieversList.length} (Type: ${rawRelievers.runtimeType})',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Relievers List
                              if (relieversList.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFAF5FF),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFE9D5FF),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons
                                                .supervised_user_circle_rounded,
                                            size: 16,
                                            color: Color(0xFF6B21A8),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Assigned Relievers (${relieversList.length}):',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF6B21A8),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: relieversList.map<Widget>((
                                          r,
                                        ) {
                                          final name =
                                              r['full_name']?.toString() ??
                                              'Reliever';
                                          final phone =
                                              r['phone_number']?.toString() ??
                                              '';
                                          final bool rActive =
                                              r['is_active'] != false;

                                          return Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: rActive
                                                    ? const Color(0xFFD8B4FE)
                                                    : Colors.grey.shade300,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.person_pin_rounded,
                                                  size: 16,
                                                  color: rActive
                                                      ? const Color(0xFF7C3AED)
                                                      : Colors.grey,
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '$name (+91 $phone)',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: rActive
                                                        ? const Color(
                                                            0xFF581C87,
                                                          )
                                                        : Colors.grey,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                InkWell(
                                                  onTap: _isProcessing
                                                      ? null
                                                      : () => _handleDeleteReliever(r),
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: const Padding(
                                                    padding: EdgeInsets.all(2),
                                                    child: Icon(
                                                      Icons.close_rounded,
                                                      size: 15,
                                                      color: Colors.red,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 10),
                              const Divider(height: 1),
                              const SizedBox(height: 8),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.vpn_key_rounded,
                                      color: Color(0xFFB45309),
                                      size: 19,
                                    ),
                                    tooltip: 'Reset PIN (4-Digit)',
                                    onPressed: _isProcessing
                                        ? null
                                        : () => _handleGeneratePin(sup),
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(
                                      Icons.person_add_alt_1_rounded,
                                      size: 16,
                                      color: Color(0xFF7C3AED),
                                    ),
                                    label: const Text(
                                      'Add Reliever',
                                      style: TextStyle(
                                        color: Color(0xFF7C3AED),
                                        fontSize: 12,
                                      ),
                                    ),
                                    onPressed: _isProcessing
                                        ? null
                                        : () => _showAddRelieverDialog(sup),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.red,
                                      size: 19,
                                    ),
                                    tooltip: 'Delete Supervisor',
                                    onPressed: _isProcessing
                                        ? null
                                        : () => _handleDeleteSupervisor(sup),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
