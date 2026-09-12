import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/utils/display_formatters.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/operator_model.dart';
import 'staff_provider.dart';
import 'add_edit_operator_screen.dart';

class StaffListScreen extends ConsumerStatefulWidget {
  const StaffListScreen({super.key});

  @override
  ConsumerState<StaffListScreen> createState() => _StaffListScreenState();
}

class _StaffListScreenState extends ConsumerState<StaffListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isResettingPin = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _showPinDialog(String operatorName, String tempPin) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: Color(0xFF059669)),
            SizedBox(width: 8),
            Text(
              'Operator PIN Reset',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Generated 4-digit login PIN for $operatorName:'),
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
                      tempPin,
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
                        Clipboard.setData(ClipboardData(text: tempPin));
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
            const Text(
              'Share this PIN with the operator. They will enter this PIN and configure their permanent PIN on their next login.',
              style: TextStyle(fontSize: 12.5, color: Colors.black87),
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

  Future<void> _handleResetOperatorPin(OperatorModel op) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: Color(0xFFB45309)),
            SizedBox(width: 8),
            Text(
              'Reset Operator PIN',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          'Generate a new temporary 4-digit PIN for ${op.fullName}?\n\n'
          'The temporary PIN will be displayed on screen so you can share it directly with the operator.',
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

    setState(() => _isResettingPin = true);

    try {
      final tempPin = await ref
          .read(authNotifierProvider.notifier)
          .supervisorResetOperatorPin(op.phoneNumber);

      if (mounted) {
        _showPinDialog(op.fullName, tempPin);
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
      if (mounted) {
        setState(() => _isResettingPin = false);
      }
    }
  }

  Widget _buildStatutoryTag(
    String label,
    String? value,
    Color bgColor,
    Color textColor,
  ) {
    final displayVal = (value != null && value.trim().isNotEmpty)
        ? (label == 'DOJ' ? formatDisplayDate(value) : value.trim())
        : '-';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: textColor.withOpacity(0.18)),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(fontSize: 11, color: textColor),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: displayVal),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: RefreshIndicator(
        color: const Color(0xFF1E3A8A),
        onRefresh: () async => ref.invalidate(staffListProvider),
        child: staffAsync.when(
          data: (staff) {
            final filteredStaff = staff.where((op) {
              final query = _searchQuery.toLowerCase();
              final name = op.fullName.toLowerCase();
              final phone = op.phoneNumber.toLowerCase();
              final empCode = (op.empCode ?? '').toLowerCase();
              final bio = (op.biometricId ?? '').toLowerCase();
              final bmrcl = (op.bmrclId ?? '').toLowerCase();
              final father = (op.fatherName ?? '').toLowerCase();
              return name.contains(query) ||
                  phone.contains(query) ||
                  empCode.contains(query) ||
                  bio.contains(query) ||
                  bmrcl.contains(query) ||
                  father.contains(query);
            }).toList();

            return Column(
              children: [
                // Search & Metrics Header Strip
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.people_alt_rounded,
                                  color: Color(0xFF1E3A8A),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Operator Directory',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E3A8A),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${staff.length} Total',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _searchController,
                        onChanged: (val) =>
                            setState(() => _searchQuery = val.trim()),
                        decoration: InputDecoration(
                          hintText:
                              'Search by Name, Phone, Emp Code, Bio ID, Father...',
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: Color(0xFF64748B),
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFFF1F5F9),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                            horizontal: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Staff Cards List
                Expanded(
                  child: filteredStaff.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 140),
                            Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.person_search_rounded,
                                    size: 48,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    staff.isEmpty
                                        ? 'No operators found. Tap + below to add.'
                                        : 'No operators matched "$_searchQuery"',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: filteredStaff.length,
                          itemBuilder: (context, idx) {
                            final op = filteredStaff[idx];
                            final isFaceReg = op.isFaceRegistered == true;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.02),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        CircleAvatar(
                                          radius: 20,
                                          backgroundColor: const Color(
                                            0xFF1E3A8A,
                                          ),
                                          child: Text(
                                            op.fullName.isNotEmpty
                                                ? op.fullName[0].toUpperCase()
                                                : 'U',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      op.fullName,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15.5,
                                                        color: Color(
                                                          0xFF0F172A,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Icon(
                                                    isFaceReg
                                                        ? Icons
                                                              .check_circle_rounded
                                                        : Icons.cancel_outlined,
                                                    size: 15,
                                                    color: isFaceReg
                                                        ? const Color(
                                                            0xFF059669,
                                                          )
                                                        : Colors.orange,
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              InkWell(
                                                onTap: () => _makePhoneCall(
                                                  op.phoneNumber,
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.phone_rounded,
                                                      size: 13,
                                                      color: Color(0xFF059669),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      op.phoneNumber,
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF2563EB,
                                                        ),
                                                        fontSize: 12.5,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: const Color(
                                              0xFFB45309,
                                            ),
                                            side: const BorderSide(
                                              color: Color(0xFFF59E0B),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            minimumSize: const Size(0, 32),
                                          ),
                                          icon: const Icon(
                                            Icons.vpn_key_rounded,
                                            size: 14,
                                          ),
                                          label: const Text(
                                            'PIN',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          onPressed: _isResettingPin
                                              ? null
                                              : () =>
                                                    _handleResetOperatorPin(op),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit_outlined,
                                            color: Color(0xFF2563EB),
                                            size: 20,
                                          ),
                                          onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  AddEditOperatorScreen(
                                                    operator: op,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            color: Colors.redAccent,
                                            size: 20,
                                          ),
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text(
                                                  'Delete Operator',
                                                ),
                                                content: Text(
                                                  'Delete ${op.fullName}?',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          ctx,
                                                          false,
                                                        ),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  ElevatedButton(
                                                    style:
                                                        ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.red,
                                                        ),
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          ctx,
                                                          true,
                                                        ),
                                                    child: const Text(
                                                      'Delete',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              await ref
                                                  .read(
                                                    staffActionNotifierProvider
                                                        .notifier,
                                                  )
                                                  .deleteOperator(op.id);
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),

                                    // Statutory & Identity Details (Form 'T' + Machine ID)
                                    // Statutory & Identity Details (Form 'T')
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        _buildStatutoryTag(
                                          'Emp Code',
                                          op.empCode,
                                          const Color(0xFFEFF6FF),
                                          const Color(0xFF1E3A8A),
                                        ),
                                        _buildStatutoryTag(
                                          'Bio ID',
                                          op.biometricId,
                                          const Color(0xFFFAF5FF),
                                          const Color(0xFF7C3AED),
                                        ),
                                        _buildStatutoryTag(
                                          'BMRCL',
                                          op.bmrclId,
                                          const Color(0xFFF0FDF4),
                                          const Color(0xFF15803D),
                                        ),
                                        _buildStatutoryTag(
                                          'Father',
                                          op.fatherName,
                                          const Color(0xFFFFFBEB),
                                          const Color(0xFFB45309),
                                        ),
                                        _buildStatutoryTag(
                                          'DOJ',
                                          op.doj,
                                          const Color(0xFFF1F5F9),
                                          const Color(0xFF334155),
                                        ),
                                        _buildStatutoryTag(
                                          'ESI',
                                          op.esiNo,
                                          const Color(0xFFF1F5F9),
                                          const Color(0xFF475569),
                                        ),
                                        _buildStatutoryTag(
                                          'UAN',
                                          op.uanNo,
                                          const Color(0xFFF1F5F9),
                                          const Color(0xFF475569),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
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
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'staff_add_fab',
        backgroundColor: const Color(0xFF1E3A8A),
        foregroundColor: Colors.white,
        elevation: 3,
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AddEditOperatorScreen()),
        ),
        icon: const Icon(Icons.person_add_rounded),
        label: const Text(
          'Add Staff',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
