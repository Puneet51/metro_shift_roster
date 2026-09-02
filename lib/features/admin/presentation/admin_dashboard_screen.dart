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

    showDialog(
      context: context,
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
                      'If a supervisor resigns, change their phone number or promote their reliever in 1 click.',
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
                          : 'Login and punch blocked',
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
              onPressed: () => Navigator.pop(ctx),
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
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final user = ref.read(authNotifierProvider).user;
                final orgId =
                    user?.orgId ?? '00000000-0000-0000-0000-000000000001';

                if (supervisor == null) {
                  final profileData = {
                    'org_id': orgId,
                    'full_name': nameCtrl.text.trim(),
                    'phone_number': phoneCtrl.text.trim(),
                    'role': 'supervisor',
                    'is_active': isActive,
                    'is_reliever': isRelieverCreation,
                    'parent_supervisor_id': parentSupervisor?['id'],
                  };

                  await SupabaseService.client
                      .from('profiles')
                      .insert(profileData);
                } else {
                  await SupabaseService.client
                      .from('profiles')
                      .update({
                        'full_name': nameCtrl.text.trim(),
                        'phone_number': phoneCtrl.text.trim(),
                        'is_active': isActive,
                      })
                      .eq('id', supervisor['id']);
                }
                ref.invalidate(adminSupervisorsListProvider);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text(
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
        content: Text('Remove ${person['full_name']} from the organization?'),
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
    if (confirm == true) {
      await SupabaseService.client
          .from('profiles')
          .delete()
          .eq('id', person['id']);
      ref.invalidate(adminSupervisorsListProvider);
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
                        // Upsert directly into app_versions table
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
          // STRICT FILTER: A profile is a reliever if is_reliever == true OR has a parent_supervisor_id
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

          final relievers = allProfiles
              .where((s) => checkIsReliever(s))
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

                          // Only grab relievers that belong to THIS primary supervisor
                          final linkedRelievers = relievers
                              .where(
                                (r) =>
                                    r['parent_supervisor_id'] == primary['id'],
                              )
                              .toList();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isActive
                                    ? const Color(0xFFE2E8F0)
                                    : const Color(0xFFFCA5A5),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.02),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                // Primary Supervisor Row
                                Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor: isActive
                                            ? const Color(0xFF1E3A8A)
                                            : Colors.grey.shade400,
                                        child: Text(
                                          primary['full_name'] != null &&
                                                  (primary['full_name']
                                                          as String)
                                                      .isNotEmpty
                                              ? primary['full_name'][0]
                                                    .toUpperCase()
                                              : 'S',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
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
                                              primary['full_name'] ??
                                                  'Supervisor',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15.5,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Phone: +91 ${primary['phone_number']}',
                                              style: const TextStyle(
                                                color: Colors.black54,
                                                fontSize: 12.5,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              'Full Shared Access: Same Stations & Rosters',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.blue.shade700,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Transform.scale(
                                            scale: 0.8,
                                            child: Switch(
                                              value: isActive,
                                              activeColor: const Color(
                                                0xFF059669,
                                              ),
                                              onChanged: (val) async {
                                                await SupabaseService.client
                                                    .from('profiles')
                                                    .update({'is_active': val})
                                                    .eq('id', primary['id']);
                                                ref.invalidate(
                                                  adminSupervisorsListProvider,
                                                );
                                              },
                                            ),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              TextButton.icon(
                                                style: TextButton.styleFrom(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                      ),
                                                  minimumSize: Size.zero,
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                                icon: const Icon(
                                                  Icons.person_add_alt_rounded,
                                                  size: 15,
                                                  color: Color(0xFF7C3AED),
                                                ),
                                                label: const Text(
                                                  'Add Reliever',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF7C3AED),
                                                  ),
                                                ),
                                                onPressed: () =>
                                                    _showAddEditSupervisorDialog(
                                                      parentSupervisor: primary,
                                                    ),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 19,
                                                  color: Color(0xFF2563EB),
                                                ),
                                                onPressed: () =>
                                                    _showAddEditSupervisorDialog(
                                                      supervisor: primary,
                                                    ),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  size: 19,
                                                  color: Colors.redAccent,
                                                ),
                                                onPressed: () =>
                                                    _deleteSupervisor(primary),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Strictly NESTED Relievers inside this Primary Supervisor Card
                                if (linkedRelievers.isNotEmpty)
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.only(
                                      left: 14,
                                      right: 14,
                                      bottom: 12,
                                    ),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.people_outline,
                                              size: 14,
                                              color: Color(0xFF7C3AED),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              'Reliever Supervisor (${linkedRelievers.length})',
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF7C3AED),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        ...linkedRelievers.map((reliever) {
                                          final rActive =
                                              reliever['is_active'] == true;
                                          return Container(
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 3,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: const Color(0xFFE2E8F0),
                                              ),
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons
                                                      .subdirectory_arrow_right_rounded,
                                                  size: 16,
                                                  color: Color(0xFF7C3AED),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Text(
                                                            reliever['full_name'] ??
                                                                'Reliever',
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .bold,
                                                                  fontSize: 13,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            width: 6,
                                                          ),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 5,
                                                                  vertical: 1,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  const Color(
                                                                    0xFFF3E8FF,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    4,
                                                                  ),
                                                            ),
                                                            child: const Text(
                                                              'RELIEVER',
                                                              style: TextStyle(
                                                                fontSize: 9,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color: Color(
                                                                  0xFF7C3AED,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      Text(
                                                        'Phone: +91 ${reliever['phone_number']}',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: Colors
                                                              .grey
                                                              .shade600,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                ElevatedButton.icon(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        const Color(0xFF059669),
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 6,
                                                        ),
                                                    minimumSize: Size.zero,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                  ),
                                                  icon: const Icon(
                                                    Icons.upgrade_rounded,
                                                    size: 14,
                                                  ),
                                                  label: const Text(
                                                    'Promote to Primary',
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  ),
                                                  onPressed: () =>
                                                      _promoteReliever(
                                                        reliever,
                                                      ),
                                                ),
                                                const SizedBox(width: 4),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.edit_outlined,
                                                    size: 17,
                                                    color: Color(0xFF2563EB),
                                                  ),
                                                  onPressed: () =>
                                                      _showAddEditSupervisorDialog(
                                                        supervisor: reliever,
                                                      ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons
                                                        .delete_outline_rounded,
                                                    size: 17,
                                                    color: Colors.redAccent,
                                                  ),
                                                  onPressed: () =>
                                                      _deleteSupervisor(
                                                        reliever,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
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
