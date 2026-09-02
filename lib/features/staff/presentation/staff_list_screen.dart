import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
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

  Widget _buildStatutoryTag(
    String label,
    String value,
    Color bgColor,
    Color textColor,
  ) {
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
            TextSpan(text: value.isNotEmpty ? value : '-'),
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
              final empCode = (op.empCode ?? op.companyId ?? '').toLowerCase();
              final bio = (op.biometricId ?? '').toLowerCase();
              final bmrcl = (op.bmrclId ?? '').toLowerCase();
              return name.contains(query) ||
                  phone.contains(query) ||
                  empCode.contains(query) ||
                  bio.contains(query) ||
                  bmrcl.contains(query);
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
                              'Search by Name, Phone, Emp Code, Bio ID...',
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
                            final empCode = op.empCode ?? op.companyId ?? '-';
                            final bioId = op.biometricId ?? '-';
                            final bmrclId = op.bmrclId ?? '-';
                            final fatherName = op.fatherName ?? '-';
                            final doj = op.doj ?? '-';
                            final esi = op.esiNo ?? '-';
                            final uan = op.uanNo ?? '-';
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

                                    // Statutory & Identity Details (Matching Form 'T')
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        _buildStatutoryTag(
                                          'Emp Code',
                                          empCode,
                                          const Color(0xFFEFF6FF),
                                          const Color(0xFF1E3A8A),
                                        ),
                                        _buildStatutoryTag(
                                          'Bio ID',
                                          bioId,
                                          const Color(0xFFFAF5FF),
                                          const Color(0xFF7C3AED),
                                        ),
                                        _buildStatutoryTag(
                                          'BMRCL',
                                          bmrclId,
                                          const Color(0xFFF0FDF4),
                                          const Color(0xFF15803D),
                                        ),
                                        _buildStatutoryTag(
                                          "Father",
                                          fatherName,
                                          const Color(0xFFFFFBEB),
                                          const Color(0xFFB45309),
                                        ),
                                        _buildStatutoryTag(
                                          'DOJ',
                                          doj,
                                          const Color(0xFFF1F5F9),
                                          const Color(0xFF334155),
                                        ),
                                        _buildStatutoryTag(
                                          'ESI',
                                          esi,
                                          const Color(0xFFF1F5F9),
                                          const Color(0xFF475569),
                                        ),
                                        _buildStatutoryTag(
                                          'UAN',
                                          uan,
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
