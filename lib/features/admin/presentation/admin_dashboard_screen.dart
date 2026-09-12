import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import 'package:metro_shift_roster/core/services/app_update_service.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'admin_provider.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  bool _isProcessing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final updateInfo = await AppUpdateService.checkForUpdate();
      if (updateInfo != null && mounted) {
        AppUpdateService.showUpdateDialog(context, updateInfo);
      }
    });
  }

  void _showPinDialog({
    required String title,
    required String recipientName,
    required String pin,
    required String description,
  }) {
    showDialog(
      context: context,
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
            Text('Generated Login PIN for $recipientName:'),
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
                child: SelectableText(
                  pin,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                    color: Color(0xFF1E3A8A),
                  ),
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

  Future<void> _handleResetSupervisorPin(
    Map<String, dynamic> supervisor,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: Color(0xFFB45309)),
            SizedBox(width: 8),
            Text(
              'Reset Login PIN',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Generate a new temporary login PIN for ${supervisor['full_name']}?\n\n'
          'The temporary PIN will be displayed on your screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A8A),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Generate PIN',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final currentAdmin = ref.read(authNotifierProvider).user;
      final res = await SupabaseService.client.rpc(
        'admin_reset_supervisor_pin',
        params: {
          'p_supervisor_id': supervisor['id'],
          'p_admin_id': currentAdmin!.id,
        },
      );

      final data = res as Map<String, dynamic>;
      if (data['success'] != true) {
        throw Exception(data['error'] ?? 'Failed to reset PIN');
      }

      final tempPin = data['temp_pin'].toString();
      if (mounted) {
        _showPinDialog(
          title: 'Supervisor PIN Reset',
          recipientName: supervisor['full_name'] ?? 'Supervisor',
          pin: tempPin,
          description:
              'This temporary PIN has been registered. Share it directly with the supervisor.',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed: ${e.toString().replaceAll('Exception: ', '')}',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showAddEditSupervisorDialog({
    Map<String, dynamic>? supervisor,
    Map<String, dynamic>? parentSupervisor,
  }) {
    final bool isRelieverCreation = parentSupervisor != null;
    final nameCtrl = TextEditingController(
      text: supervisor?['full_name'] ?? '',
    );
    final phoneCtrl = TextEditingController(
      text: supervisor?['phone_number'] ?? '',
    );
    bool isActive = supervisor?['is_active'] ?? true;
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            supervisor == null
                ? (isRelieverCreation
                      ? 'Add Reliever for ${parentSupervisor['full_name']}'
                      : 'Add Primary Supervisor')
                : 'Edit Supervisor Details',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (parentSupervisor != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3E8FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFD8B4FE)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.link_rounded,
                            color: Color(0xFF7C3AED),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Linked directly under ${parentSupervisor['full_name']}. Shares all stations & rosters.',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B21A8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  TextFormField(
                    controller: nameCtrl,
                    decoration: InputDecoration(
                      labelText: isRelieverCreation
                          ? 'Reliever Full Name'
                          : 'Supervisor Full Name',
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Name required' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    decoration: const InputDecoration(
                      labelText: '10-Digit Mobile Number',
                      prefixText: '+91 ',
                      prefixIcon: Icon(Icons.phone_android_rounded),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v == null || v.trim().length != 10
                        ? 'Enter valid 10-digit phone number'
                        : null,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Text(
                      'Account will be created with no temporary PIN. The supervisor will set their own permanent 4-digit PIN on first login.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF1E3A8A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Account Active Status',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: Text(
                      isActive
                          ? 'Can login and manage shift rosters'
                          : 'Login blocked',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isActive
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                    value: isActive,
                    activeColor: const Color(0xFF059669),
                    onChanged: (val) => setDialogState(() => isActive = val),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setDialogState(() => isSaving = true);
                      try {
                        final cleanPhone = phoneCtrl.text
                            .replaceAll(RegExp(r'\D'), '')
                            .trim();

                        if (supervisor == null) {
                          final user = ref.read(authNotifierProvider).user;
                          final orgId = user?.orgId ?? '';

                          if (isRelieverCreation) {
                            final res = await SupabaseService.client.rpc(
                              'add_supervisor_reliever',
                              params: {
                                'p_supervisor_id': parentSupervisor['id'],
                                'p_full_name': nameCtrl.text.trim(),
                                'p_phone_number': cleanPhone,
                              },
                            );
                            final data = res as Map<String, dynamic>;
                            if (data['success'] != true) {
                              throw Exception(
                                data['error'] ?? 'Reliever registration failed',
                              );
                            }
                          } else {
                            final res = await SupabaseService.client.rpc(
                              'create_native_supervisor',
                              params: {
                                'p_full_name': nameCtrl.text.trim(),
                                'p_phone_number': cleanPhone,
                                if (orgId.isNotEmpty) 'p_org_id': orgId,
                              },
                            );
                            final data = res as Map<String, dynamic>;
                            if (data['success'] != true) {
                              throw Exception(
                                data['error'] ?? 'Registration failed',
                              );
                            }
                          }

                          ref.invalidate(adminSupervisorsListProvider);

                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  isRelieverCreation
                                      ? '${nameCtrl.text.trim()} was created. They will set their own PIN on first login.'
                                      : '${nameCtrl.text.trim()} was created. They will set their own PIN on first login.',
                                ),
                                backgroundColor: const Color(0xFF059669),
                              ),
                            );
                          }
                        } else {
                          await SupabaseService.client
                              .from('profiles')
                              .update({
                                'full_name': nameCtrl.text.trim(),
                                'phone_number': cleanPhone,
                                'is_active': isActive,
                              })
                              .eq('id', supervisor['id']);

                          ref.invalidate(adminSupervisorsListProvider);
                          if (ctx.mounted) Navigator.pop(ctx);
                        }
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Failed: ${e.toString().replaceAll('Exception: ', '')}',
                              ),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Save Details',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _promoteReliever(Map<String, dynamic> reliever) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Promote to Primary Supervisor'),
        content: Text(
          'Promote ${reliever['full_name']} to Primary Supervisor?\n\nThe previous supervisor will be deactivated, and ${reliever['full_name']} will take full ownership of all stations and rosters.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Promote Now',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SupabaseService.client.rpc(
        'promote_reliever_to_primary',
        params: {'p_reliever_id': reliever['id']},
      );
      ref.invalidate(adminSupervisorsListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${reliever['full_name']} is now the Primary Supervisor!',
            ),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    }
  }

  Future<void> _deleteSupervisor(Map<String, dynamic> person) async {
    final isRel = person['is_reliever'] == true;


    final confirm = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(isRel ? 'Delete Reliever' : 'Delete Supervisor'),
        content: Text(
          isRel
              ? 'Remove ${person['full_name']} from the organization?'
              : 'Delete ${person['full_name']} and all of their organization data?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final authUser = ref.read(authNotifierProvider).user;



    if (authUser == null || authUser.role != 'admin') {

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Admin session is not available. Please sign in again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _isProcessing = true);
    try {

      await ref.read(adminRepositoryProvider).deleteSupervisor(
        supervisorId: person['id'].toString(),
        adminId: authUser.id,
      );


      if (mounted) {
        ref.invalidate(adminSupervisorsListProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRel ? 'Reliever deleted successfully' : 'Supervisor deleted successfully',
            ),
          ),
        );
      }
    } catch (e, st) {


      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delete failed: ${e.toString().replaceAll('Exception: ', '')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showAppVersionManagementDialog() {
    final versionCtrl = TextEditingController(text: '1.0.1');
    final minVersionCtrl = TextEditingController(text: '1.0.0');
    final urlCtrl = TextEditingController(
      text: 'https://metroshiftroster.web.app',
    );
    final notesCtrl = TextEditingController(
      text: 'Multi-supervisor data sharing & stability improvements',
    );
    bool force = true;
    String platform = 'android';
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Manage App Updates & Release',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Target Platform',
                    border: OutlineInputBorder(),
                  ),
                  value: platform,
                  items: const [
                    DropdownMenuItem(
                      value: 'android',
                      child: Text('Android (APK / Play Store)'),
                    ),
                    DropdownMenuItem(
                      value: 'web',
                      child: Text('Web / PWA Portal'),
                    ),
                    DropdownMenuItem(
                      value: 'ios',
                      child: Text('iOS (App Store)'),
                    ),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => platform = v ?? 'android'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: versionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Latest Released Version (e.g. 1.0.1)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: minVersionCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Minimum Required Version (e.g. 1.0.0)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Store / Direct Download URL',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Release Highlights',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: force
                        ? const Color(0xFFFEF2F2)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: force
                          ? const Color(0xFFFCA5A5)
                          : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: SwitchListTile(
                    title: const Text(
                      'Force Mandatory Update',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: Text(
                      force
                          ? 'BLOCKS all users until app is updated'
                          : 'Optional prompt on screen',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: force
                            ? const Color(0xFFDC2626)
                            : Colors.grey.shade600,
                      ),
                    ),
                    activeColor: const Color(0xFFDC2626),
                    value: force,
                    onChanged: (v) => setDialogState(() => force = v),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      setDialogState(() => isSaving = true);
                      try {
                        await SupabaseService.client
                            .from('app_versions')
                            .upsert({
                              'platform': platform,
                              'version': versionCtrl.text.trim(),
                              'latest_version': versionCtrl.text.trim(),
                              'min_version': minVersionCtrl.text.trim(),
                              'min_supported_version': minVersionCtrl.text
                                  .trim(),
                              'update_url': urlCtrl.text.trim(),
                              'release_notes': notesCtrl.text.trim(),
                              'force_update': force,
                              'updated_at': DateTime.now().toIso8601String(),
                            }, onConflict: 'platform');

                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'App update configuration published successfully!',
                              ),
                              backgroundColor: Color(0xFF059669),
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to publish: $e'),
                              backgroundColor: Colors.redAccent,
                            ),
                          );
                        }
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Publish Update Configuration',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _countBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF475569)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
        ],
      ),
    );
  }

  Widget _buildProfessionalSupervisorCard(
    Map<String, dynamic> primary,
    List<Map<String, dynamic>> linkedRelievers,
  ) {
    final isActive = primary['is_active'] == true;
    final name = primary['full_name']?.toString().trim().isNotEmpty == true
        ? primary['full_name'].toString().trim()
        : 'Supervisor';
    final phone = primary['phone_number']?.toString() ?? '';
    final stationCount = primary['station_count'] ?? 0;
    final staffCount = primary['staff_count'] ?? 0;

    Widget actionButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
      required Color color,
    }) {
      return Tooltip(
        message: tooltip,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.14)),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            splashRadius: 20,
            onPressed: onPressed,
            icon: Icon(icon, size: 20, color: color),
          ),
        ),
      );
    }

    return Container(
      key: ValueKey('sup_${primary['id']}_${linkedRelievers.length}'),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? const Color(0xFFE2E8F0) : const Color(0xFFFECACA),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 23,
                  backgroundColor: isActive
                      ? const Color(0xFF1E3A8A)
                      : Colors.grey.shade400,
                  child: Text(
                    name.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '+91 $phone',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 7,
                        runSpacing: 6,
                        children: [
                          _countBadge(Icons.subway_rounded, '$stationCount Stations'),
                          _countBadge(Icons.people_alt_rounded, '$staffCount Staff'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Transform.scale(
                  scale: 0.82,
                  child: Switch(
                    value: isActive,
                    activeColor: const Color(0xFF059669),
                    onChanged: (val) async {
                      await SupabaseService.client
                          .from('profiles')
                          .update({'is_active': val})
                          .eq('id', primary['id']);
                      ref.invalidate(adminSupervisorsListProvider);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
            const SizedBox(height: 12),
            Row(
              children: [
                actionButton(
                  icon: Icons.vpn_key_rounded,
                  tooltip: 'Generate / Reset PIN',
                  color: const Color(0xFFB45309),
                  onPressed: _isProcessing ? null : () => _handleResetSupervisorPin(primary),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE9D5FF)),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _isProcessing
                          ? null
                          : () => _showAddEditSupervisorDialog(parentSupervisor: primary),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.person_add_alt_rounded, size: 19, color: Color(0xFF7C3AED)),
                          SizedBox(width: 7),
                          Text(
                            'Add Reliever',
                            style: TextStyle(
                              color: Color(0xFF6D28D9),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                actionButton(
                  icon: Icons.edit_outlined,
                  tooltip: 'Edit Supervisor',
                  color: const Color(0xFF2563EB),
                  onPressed: _isProcessing ? null : () => _showAddEditSupervisorDialog(supervisor: primary),
                ),
                const SizedBox(width: 9),
                actionButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: 'Delete Supervisor',
                  color: const Color(0xFFDC2626),
                  onPressed: _isProcessing ? null : () => _deleteSupervisor(primary),
                ),
              ],
            ),
            if (linkedRelievers.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF5FF),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: const Color(0xFFE9D5FF)),
                ),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.supervised_user_circle_rounded, size: 19, color: Color(0xFF7C3AED)),
                        const SizedBox(width: 7),
                        Text(
                          'Relievers  •  ${linkedRelievers.length}',
                          style: const TextStyle(
                            color: Color(0xFF581C87),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ...linkedRelievers.map((reliever) {
                      final relieverName = reliever['full_name']?.toString().trim().isNotEmpty == true
                          ? reliever['full_name'].toString().trim()
                          : 'Reliever';
                      final relieverPhone = reliever['phone_number']?.toString() ?? '';
                      final relieverActive = reliever['is_active'] != false;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.fromLTRB(12, 11, 10, 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE9D5FF)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: relieverActive ? const Color(0xFFF3E8FF) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Icon(
                                    Icons.person_outline_rounded,
                                    size: 19,
                                    color: relieverActive ? const Color(0xFF7C3AED) : const Color(0xFF94A3B8),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        relieverName,
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1E293B),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '+91 $relieverPhone',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: Color(0xFF64748B),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: relieverActive ? const Color(0xFFF3E8FF) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    relieverActive ? 'ACTIVE' : 'INACTIVE',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: relieverActive ? const Color(0xFF7C3AED) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                actionButton(
                                  icon: Icons.vpn_key_rounded,
                                  tooltip: 'Generate / Reset PIN',
                                  color: const Color(0xFFB45309),
                                  onPressed: _isProcessing ? null : () => _handleResetSupervisorPin(reliever),
                                ),
                                const SizedBox(width: 8),
                                actionButton(
                                  icon: Icons.upgrade_rounded,
                                  tooltip: 'Promote to Primary',
                                  color: const Color(0xFF059669),
                                  onPressed: _isProcessing ? null : () => _promoteReliever(reliever),
                                ),
                                const SizedBox(width: 8),
                                actionButton(
                                  icon: Icons.edit_outlined,
                                  tooltip: 'Edit Reliever',
                                  color: const Color(0xFF2563EB),
                                  onPressed: _isProcessing ? null : () => _showAddEditSupervisorDialog(supervisor: reliever),
                                ),
                                const SizedBox(width: 8),
                                actionButton(
                                  icon: Icons.delete_outline_rounded,
                                  tooltip: 'Delete Reliever',
                                  color: const Color(0xFFDC2626),
                                  onPressed: _isProcessing ? null : () => _deleteSupervisor(reliever),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supervisorsAsync = ref.watch(adminSupervisorsListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A8A),
        title: const Text(
          'Metro Shift Roster — Central Admin Portal',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.system_update_alt_rounded),
            tooltip: 'App Version & Release Control',
            onPressed: _showAppVersionManagementDialog,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign Out',
            onPressed: () => ref.read(authNotifierProvider.notifier).logout(),
          ),
        ],
      ),
      body: supervisorsAsync.when(
        data: (allProfiles) {
          bool checkIsReliever(Map<String, dynamic> item) {
            final isRel = item['is_reliever'];
            final parentId = item['parent_supervisor_id'];
            return isRel == true ||
                isRel == 'true' ||
                (parentId != null && parentId.toString().isNotEmpty);
          }

          final primarySupervisors = allProfiles
              .where((s) => !checkIsReliever(s))
              .toList();

          final totalStations = allProfiles.isNotEmpty
              ? allProfiles.first['total_stations'] ?? 0
              : 0;
          final totalOperators = allProfiles.isNotEmpty
              ? allProfiles.first['total_operators'] ?? 0
              : 0;

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Supervisors: ${primarySupervisors.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        Chip(
                          avatar: const Icon(
                            Icons.subway_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                          label: Text(
                            '$totalStations Stations',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          backgroundColor: const Color(0xFF1E3A8A),
                        ),
                        Chip(
                          avatar: const Icon(
                            Icons.people_alt_rounded,
                            size: 15,
                            color: Colors.white,
                          ),
                          label: Text(
                            '$totalOperators Staff',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          backgroundColor: const Color(0xFF0D9488),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),

              Expanded(
                child: primarySupervisors.isEmpty
                    ? const Center(
                        child: Text(
                          'No primary supervisors registered. Tap + Add Supervisor below.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: primarySupervisors.length,
                        itemBuilder: (ctx, i) {
                          final primary = primarySupervisors[i];
                          final isActive = primary['is_active'] == true;

                          final List<Map<String, dynamic>> linkedRelievers = [];

                          final rawRelievers = primary['relievers'];
                          if (rawRelievers is List) {
                            for (final r in rawRelievers) {
                              if (r is Map) {
                                linkedRelievers.add(
                                  Map<String, dynamic>.from(r),
                                );
                              }
                            }
                          } else if (rawRelievers is String &&
                              rawRelievers.trim().isNotEmpty) {
                            try {
                              final decoded = jsonDecode(rawRelievers);
                              if (decoded is List) {
                                for (final r in decoded) {
                                  if (r is Map) {
                                    linkedRelievers.add(
                                      Map<String, dynamic>.from(r),
                                    );
                                  }
                                }
                              }
                            } catch (_) {}
                          }

                          if (linkedRelievers.isEmpty) {
                            for (final p in allProfiles) {
                              if (checkIsReliever(p) &&
                                  p['parent_supervisor_id'] == primary['id']) {
                                linkedRelievers.add(
                                  Map<String, dynamic>.from(p),
                                );
                              }
                            }
                          }

                          return _buildProfessionalSupervisorCard(primary, linkedRelievers);
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF1E3A8A)),
        ),
        error: (e, _) => Center(child: Text('Error loading supervisors: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        onPressed: () => _showAddEditSupervisorDialog(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text(
          'Add Supervisor',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
