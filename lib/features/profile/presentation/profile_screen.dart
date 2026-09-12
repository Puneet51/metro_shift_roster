import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:camera/camera.dart';
import 'package:intl/intl.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/core/services/face_biometric_service.dart';
import 'package:metro_shift_roster/features/reports/presentation/form_t_excel_generator.dart';
import 'package:metro_shift_roster/features/stations/presentation/station_provider.dart';
import 'package:metro_shift_roster/features/attendance/data/attendance_repository.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  late final TextEditingController _companyController;
  late final TextEditingController _bmrclController;
  late final TextEditingController _fatherController;
  late final TextEditingController _esiController;
  late final TextEditingController _uanController;

  // Supervisor PIN Generator Tab Controller
  final _operatorPhoneController = TextEditingController();
  bool _isGeneratingPin = false;

  bool _isSaving = false;
  bool _isExporting = false;
  List<dynamic> _personalAttendance = [];
  bool _isLoadingAttendance = false;
  bool _isLoadingProfile = false;
  String? _selectedExportStationId;
  Timer? _attendanceRefreshTimer;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authNotifierProvider).user;
    final isSupervisor = user?.role == 'supervisor' || user?.role == 'admin';

    // 3 tabs if supervisor/admin, 2 tabs for operator
    _tabController = TabController(length: isSupervisor ? 3 : 2, vsync: this);

    _nameController = TextEditingController(text: user?.fullName ?? '');
    _bioController = TextEditingController(text: user?.biometricId ?? '');
    _companyController = TextEditingController(
      text: user?.empCode ?? user?.companyId ?? '',
    );
    _bmrclController = TextEditingController(text: user?.bmrclId ?? '');
    _fatherController = TextEditingController(text: user?.fatherName ?? '');
    _esiController = TextEditingController(text: user?.esiNo ?? '');
    _uanController = TextEditingController(text: user?.uanNo ?? '');

    _fetchFreshProfile();
    _fetchAttendanceReport();
    _attendanceRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) { _fetchAttendanceReport(); });
  }

  Future<void> _fetchFreshProfile() async {
    final user = ref.read(authNotifierProvider).user;
    if (user == null) return;

    setState(() => _isLoadingProfile = true);
    try {
      final res = await SupabaseService.client
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (res != null && mounted) {
        _nameController.text = res['full_name']?.toString() ?? '';
        _fatherController.text = res['father_name']?.toString() ?? '';
        _companyController.text =
            (res['emp_code'] ?? res['company_id'])?.toString() ?? '';
        _bioController.text = res['biometric_id']?.toString() ?? '';
        _esiController.text = res['esi_no']?.toString() ?? '';
        _uanController.text = res['uan_no']?.toString() ?? '';
        _bmrclController.text = res['bmrcl_id']?.toString() ?? '';

        final isFaceRegistered = res['face_embedding'] != null;
        String? faceEmb;
        if (res['face_embedding'] != null) {
          faceEmb = res['face_embedding'] is String
              ? res['face_embedding']
              : jsonEncode(res['face_embedding']);
        }

        ref
            .read(authNotifierProvider.notifier)
            .setUser(
              user.copyWith(
                fullName: _nameController.text,
                fatherName: _fatherController.text,
                empCode: _companyController.text,
                biometricId: _bioController.text,
                esiNo: _esiController.text,
                uanNo: _uanController.text,
                isFaceRegistered: isFaceRegistered,
                faceEmbedding: faceEmb,
              ),
            );
      }
    } catch (e) {
      debugPrint('Error refreshing profile: $e');
    } finally {
      if (mounted) setState(() => _isLoadingProfile = false);
    }
  }

  Future<void> _fetchAttendanceReport() async {
    if (mounted) setState(() => _isLoadingAttendance = true);
    final user = ref.read(authNotifierProvider).user;
    if (user == null) {
      if (mounted) setState(() => _isLoadingAttendance = false);
      return;
    }
    try {
      final rows = await AttendanceRepository(SupabaseService.client).getMyAttendance(user.id);
      if (mounted) {
        setState(() { _personalAttendance = rows; _isLoadingAttendance = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingAttendance = false);
    }
  }

  Future<void> _handleSupervisorGeneratePin() async {
    final phone = _operatorPhoneController.text.trim();
    if (phone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please enter a valid 10-digit operator mobile number.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: Color(0xFFB45309)),
            SizedBox(width: 8),
            Text(
              'Generate Operator PIN',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Generate a new temporary login PIN for operator with phone $phone?\n\n'
          'The temporary PIN will be dispatched directly to the operator\'s notifications feed. For confidentiality, the PIN is not displayed on your screen.',
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
              'Generate & Send',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isGeneratingPin = true);
    try {
      await ref
          .read(authNotifierProvider.notifier)
          .supervisorResetOperatorPin(phone);

      if (mounted) {
        _operatorPhoneController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'A new temporary login PIN was successfully generated and sent to $phone\'s notification box.',
            ),
            backgroundColor: const Color(0xFF059669),
            duration: const Duration(seconds: 4),
          ),
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
    } finally {
      if (mounted) setState(() => _isGeneratingPin = false);
    }
  }

  @override
  void dispose() {
    _attendanceRefreshTimer?.cancel();
    _tabController.dispose();
    _nameController.dispose();
    _bioController.dispose();
    _companyController.dispose();
    _bmrclController.dispose();
    _fatherController.dispose();
    _esiController.dispose();
    _uanController.dispose();
    _operatorPhoneController.dispose();
    super.dispose();
  }

  Future<void> _registerFace() async {
    final user = ref.read(authNotifierProvider).user;
    if (user == null) return;

    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    if (!mounted) return;

    final faceService = FaceBiometricService();
    bool registrationSuccess = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _FaceRegisterDialog(
        camera: frontCamera,
        faceService: faceService,
        onRegistered: (embedding) async {
          final payload = {
            'embedding': embedding,
            'registered_at': DateTime.now().toIso8601String(),
          };

          final res = await SupabaseService.client.rpc(
            'register_user_face',
            params: {'p_user_id': user.id, 'p_embedding': payload},
          );

          final data = res as Map<String, dynamic>;
          if (data['success'] == true) {
            registrationSuccess = true;
            ref
                .read(authNotifierProvider.notifier)
                .setUser(
                  user.copyWith(
                    isFaceRegistered: true,
                    faceEmbedding: jsonEncode(embedding),
                  ),
                );
            return true;
          } else {
            throw Exception(data['error']?.toString() ?? 'Registration failed');
          }
        },
      ),
    );

    faceService.dispose();

    if (registrationSuccess && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Face Registered Successfully!'),
          backgroundColor: Color(0xFF059669),
        ),
      );
      setState(() {});
    }
  }

  String _formatDutyDate(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '');
    return d == null ? (value?.toString() ?? '-') : DateFormat('dd/MM/yyyy').format(d);
  }

  Future<void> _exportExcel() async {
    setState(() => _isExporting = true);
    final user = ref.read(authNotifierProvider).user;
    try {
      if (user != null) {
        final isSupervisor = user.role == 'supervisor' || user.role == 'admin';
        String stationId = 'all';
        String stationName = isSupervisor ? 'Metro_Station' : 'All_Stations';

        if (!isSupervisor) {
          final stations = ref.read(stationsListProvider).value ?? [];
          final selected = stations.where((s) => s.id == _selectedExportStationId).firstOrNull;
          if (selected == null) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a station before downloading Excel.')));
            return;
          }
          stationId = selected.id;
          stationName = selected.name;
        } else if (_personalAttendance.isNotEmpty) {
          final first = _personalAttendance.first;
          if (first['station_id'] != null) stationId = first['station_id'].toString();
          if (first['stations'] is Map && first['stations']['name'] != null) stationName = first['stations']['name'].toString();
        }

        await FormTExcelGenerator.generateAndDownloadExcel(
          stationId: stationId, stationName: stationName, selectedMonth: DateTime.now(),
          operatorId: isSupervisor ? null : user.id,
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authNotifierProvider).user;
    final isSupervisor = user?.role == 'supervisor' || user?.role == 'admin';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A8A),
        elevation: 0,
        title: const Text(
          'My Profile & Attendance',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF1E3A8A),
              indicatorWeight: 3,
              labelColor: const Color(0xFF1E3A8A),
              unselectedLabelColor: const Color(0xFF64748B),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
              ),
              tabs: [
                const Tab(
                  icon: Icon(Icons.person_rounded, size: 20),
                  text: 'Profile & Face ID',
                ),
                const Tab(
                  icon: Icon(Icons.table_chart_rounded, size: 20),
                  text: 'Attendance Register',
                ),
                if (isSupervisor)
                  const Tab(
                    icon: Icon(Icons.vpn_key_rounded, size: 20),
                    text: 'PIN Setup',
                  ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: Profile & Statutory Fields
          _isLoadingProfile
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF1E3A8A)),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.02),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 36,
                              backgroundColor: const Color(0xFF1E3A8A),
                              child: Text(
                                user?.fullName.isNotEmpty == true
                                    ? user!.fullName[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                  fontSize: 28,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              user?.fullName ?? '',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Phone: ${user?.phoneNumber ?? ""}',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: user?.isFaceRegistered == true
                                    ? const Color(0xFFECFDF5)
                                    : const Color(0xFFFFFBEB),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: user?.isFaceRegistered == true
                                      ? const Color(0xFF059669).withOpacity(0.3)
                                      : const Color(
                                          0xFFD97706,
                                        ).withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    user?.isFaceRegistered == true
                                        ? Icons.check_circle_rounded
                                        : Icons.warning_amber_rounded,
                                    color: user?.isFaceRegistered == true
                                        ? const Color(0xFF059669)
                                        : const Color(0xFFD97706),
                                    size: 14,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    user?.isFaceRegistered == true
                                        ? 'Face Registered'
                                        : 'Face Not Registered',
                                    style: TextStyle(
                                      color: user?.isFaceRegistered == true
                                          ? const Color(0xFF059669)
                                          : const Color(0xFFD97706),
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Personal Details',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Full Name',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _fatherController,
                              decoration: const InputDecoration(
                                labelText: "Father's Name",
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Muster Roll & Statutory Details',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _companyController,
                                    decoration: const InputDecoration(
                                      labelText: 'Emp Code',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: _bioController,
                                    decoration: const InputDecoration(
                                      labelText: 'Biometric ID',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _esiController,
                                    decoration: const InputDecoration(
                                      labelText: 'ESI Number',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: _uanController,
                                    decoration: const InputDecoration(
                                      labelText: 'UAN Number',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _bmrclController,
                              decoration: const InputDecoration(
                                labelText: 'BMRCL ID',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(
                            color: Color(0xFF1E3A8A),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(
                          Icons.face_retouching_natural_rounded,
                          color: Color(0xFF1E3A8A),
                        ),
                        label: const Text(
                          '1-Click Register / Update Face ID',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                        onPressed: _registerFace,
                      ),
                      const SizedBox(height: 10),

                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _isSaving
                            ? null
                            : () async {
                                setState(() => _isSaving = true);
                                await SupabaseService.client
                                    .from('profiles')
                                    .update({
                                      'full_name': _nameController.text.trim(),
                                      'father_name': _fatherController.text
                                          .trim(),
                                      'emp_code': _companyController.text
                                          .trim(),
                                      'company_id': _companyController.text
                                          .trim(),
                                      'biometric_id': _bioController.text
                                          .trim(),
                                      'esi_no': _esiController.text.trim(),
                                      'uan_no': _uanController.text.trim(),
                                      'bmrcl_id': _bmrclController.text.trim(),
                                    })
                                    .eq('id', user!.id);
                                setState(() => _isSaving = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Profile Saved Successfully!',
                                      ),
                                      backgroundColor: Color(0xFF059669),
                                    ),
                                  );
                                }
                              },
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Save Profile Changes',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),

          // TAB 2: Attendance Records & Download
          Column(
            children: [
              if (!isSupervisor)
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  color: Colors.white,
                  child: ref.watch(stationsListProvider).when(
                    loading: () => const InputDecorator(
                      decoration: InputDecoration(labelText: 'Station for Excel', border: OutlineInputBorder()),
                      child: Text('Loading stations...'),
                    ),
                    error: (_, __) => const InputDecorator(
                      decoration: InputDecoration(labelText: 'Station for Excel', border: OutlineInputBorder()),
                      child: Text('Unable to load stations'),
                    ),
                    data: (stations) => DropdownButtonFormField<String>(
                      value: stations.any((s) => s.id == _selectedExportStationId) ? _selectedExportStationId : null,
                      decoration: const InputDecoration(labelText: 'Station for Excel', border: OutlineInputBorder()),
                      items: stations.map((s) => DropdownMenuItem<String>(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (value) => setState(() => _selectedExportStationId = value),
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.all(12.0),
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Attendance Log',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: _isExporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.download_rounded, size: 18),
                      label: const Text(
                        'Download Excel',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                      onPressed: _isExporting ? null : _exportExcel,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE2E8F0)),

              Expanded(
                child: _isLoadingAttendance
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF1E3A8A),
                        ),
                      )
                    : _personalAttendance.isEmpty
                    ? const Center(
                        child: Text('No attendance records logged yet.'),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _personalAttendance.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final att = _personalAttendance[i];
                          final stn = att['stations'] != null
                              ? att['stations']['name']
                              : 'Station';
                          final status = (att['status'] ?? 'processing')
                              .toString()
                              .toLowerCase();

                          Color chipBg;
                          Color chipFg;
                          String chipLabel;

                          if (status == 'present') {
                            chipBg = const Color(0xFFECFDF5);
                            chipFg = const Color(0xFF059669);
                            chipLabel = 'PRESENT';
                          } else if (status == 'absent') {
                            chipBg = const Color(0xFFFEF2F2);
                            chipFg = const Color(0xFFDC2626);
                            chipLabel = 'ABSENT';
                          } else if (status == 'week_off') {
                            chipBg = const Color(0xFFFEF3C7);
                            chipFg = const Color(0xFFD97706);
                            chipLabel = 'WEEK OFF';
                          } else {
                            chipBg = const Color(0xFFEFF6FF);
                            chipFg = const Color(0xFF1E3A8A);
                            chipLabel = 'ON DUTY';
                          }

                          return Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: chipBg,
                                child: Icon(
                                  status == 'present'
                                      ? Icons.check_rounded
                                      : (status == 'absent'
                                            ? Icons.close_rounded
                                            : Icons.timer_outlined),
                                  color: chipFg,
                                ),
                              ),
                              title: Text(
                                '$stn • ${_formatDutyDate(att['duty_date'])}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              subtitle: Text(
                                status == 'present'
                                    ? 'Duty assigned'
                                    : status == 'week_off'
                                        ? 'No duty — Week Off'
                                        : 'No duty assigned — Absent',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: chipBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  chipLabel,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: chipFg,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),

          // TAB 3: Supervisor-Managed PIN Generator Tab
          if (isSupervisor)
            SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: Color(0xFF1E3A8A),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Operator PIN Setup & Reset',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          'If an operator forgot their login PIN or requires first-time access, enter their registered mobile number and tap "Generate PIN".\n\n'
                          'A secure temporary PIN will be created natively and delivered directly to the operator\'s notifications. For privacy, it is never shown here.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF1E3A8A),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  TextFormField(
                    controller: _operatorPhoneController,
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    decoration: const InputDecoration(
                      labelText: 'Operator Registered Mobile Number',
                      prefixText: '+91 ',
                      prefixIcon: Icon(Icons.phone_android),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A8A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: _isGeneratingPin
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.vpn_key_rounded),
                    label: Text(
                      _isGeneratingPin
                          ? 'Generating & Sending PIN...'
                          : 'Generate PIN',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    onPressed: _isGeneratingPin
                        ? null
                        : _handleSupervisorGeneratePin,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FaceRegisterDialog extends StatefulWidget {
  final CameraDescription camera;
  final FaceBiometricService faceService;
  final Future<bool> Function(List<double> embedding) onRegistered;

  const _FaceRegisterDialog({
    required this.camera,
    required this.faceService,
    required this.onRegistered,
  });

  @override
  State<_FaceRegisterDialog> createState() => _FaceRegisterDialogState();
}

class _FaceRegisterDialogState extends State<_FaceRegisterDialog> {
  CameraController? _controller;
  bool _isCapturing = false;
  bool _isInit = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _controller!.initialize();
    if (mounted) setState(() => _isInit = true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _captureAndRegister() async {
    if (_isCapturing ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return;
    }
    setState(() => _isCapturing = true);

    try {
      final photo = await _controller!.takePicture();
      final embedding = await widget.faceService.extractFaceEmbeddingFromFile(
        photo.path,
      );

      try {
        await File(photo.path).delete();
      } catch (_) {}

      if (embedding == null || embedding.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No face detected. Look directly at the camera.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final success = await widget.onRegistered(embedding);
      if (success && mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        '1-Click Face Registration',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
      ),
      content: SizedBox(
        height: 320,
        child: Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isInit && _controller != null)
                      CameraPreview(_controller!)
                    else
                      const Center(child: CircularProgressIndicator()),
                    Container(
                      width: 180,
                      height: 220,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(90),
                        border: Border.all(color: Colors.greenAccent, width: 3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: (_isInit && !_isCapturing)
                  ? _captureAndRegister
                  : null,
              icon: _isCapturing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.camera_alt, color: Colors.white),
              label: Text(
                _isCapturing ? 'Registering Face...' : 'Register Face Now',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCapturing ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
