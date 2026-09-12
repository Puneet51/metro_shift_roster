class OperatorModel {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String? orgId;
  final String? parentSupervisorId;
  final String? companyId;
  final String? empCode;
  final String? biometricId;
  final String? bmrclId;
  final String? fatherName;
  final String? doj;
  final String? esiNo;
  final String? uanNo;
  final bool isFaceRegistered;
  final int weekOffs;
  final bool isWeekOffToday;

  const OperatorModel({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    this.orgId,
    this.parentSupervisorId,
    this.companyId,
    this.empCode,
    this.biometricId,
    this.bmrclId,
    this.fatherName,
    this.doj,
    this.esiNo,
    this.uanNo,
    this.isFaceRegistered = false,
    this.weekOffs = 0,
    this.isWeekOffToday = false,
  });

  factory OperatorModel.fromJson(Map<String, dynamic> json) {
    return OperatorModel(
      id: json['id'] as String,
      fullName: (json['full_name'] ?? '') as String,
      phoneNumber: (json['phone_number'] ?? '') as String,
      orgId: json['org_id']?.toString(),
      parentSupervisorId: json['parent_supervisor_id']?.toString(),
      companyId: (json['company_id'] ?? json['emp_code']) as String?,
      empCode: (json['emp_code'] ?? json['company_id'])?.toString(),
      biometricId: json['biometric_id']?.toString(),
      bmrclId: json['bmrcl_id']?.toString(),
      fatherName: json['father_name']?.toString(),
      doj: json['doj']?.toString(),
      esiNo: json['esi_no']?.toString(),
      uanNo: json['uan_no']?.toString(),
      isFaceRegistered:
          json['face_embedding'] != null || json['is_face_registered'] == true,
      weekOffs: (json['week_offs'] as num?)?.toInt() ?? 0,
      isWeekOffToday: json['is_week_off_today'] == true,
    );
  }

  // Accepts map + optional named weekOffs passed by staff_repository.dart
  factory OperatorModel.fromMap(Map<String, dynamic> map, {int? weekOffs, bool? isWeekOffToday}) {
    return OperatorModel(
      id: map['id'] as String,
      fullName: (map['full_name'] ?? '') as String,
      phoneNumber: (map['phone_number'] ?? '') as String,
      orgId: map['org_id']?.toString(),
      parentSupervisorId: map['parent_supervisor_id']?.toString(),
      companyId: (map['company_id'] ?? map['emp_code']) as String?,
      empCode: (map['emp_code'] ?? map['company_id'])?.toString(),
      biometricId: map['biometric_id']?.toString(),
      bmrclId: map['bmrcl_id']?.toString(),
      fatherName: map['father_name']?.toString(),
      doj: map['doj']?.toString(),
      esiNo: map['esi_no']?.toString(),
      uanNo: map['uan_no']?.toString(),
      isFaceRegistered:
          map['face_embedding'] != null || map['is_face_registered'] == true,
      weekOffs: weekOffs ?? ((map['week_offs'] as num?)?.toInt() ?? 0),
      isWeekOffToday: isWeekOffToday ?? (map['is_week_off_today'] == true),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'phone_number': phoneNumber,
      'org_id': orgId,
      'parent_supervisor_id': parentSupervisorId,
      'company_id': companyId,
      'emp_code': empCode ?? companyId,
      'biometric_id': biometricId,
      'bmrcl_id': bmrclId,
      'father_name': fatherName,
      'doj': doj,
      'esi_no': esiNo,
      'uan_no': uanNo,
      'is_face_registered': isFaceRegistered,
      'week_offs': weekOffs,
      'is_week_off_today': isWeekOffToday,
    };
  }

  Map<String, dynamic> toMap() => toJson();
}
