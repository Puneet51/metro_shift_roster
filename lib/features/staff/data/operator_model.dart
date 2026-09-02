class OperatorModel {
  final String id;
  final String fullName;
  final String phoneNumber;
  final String? orgId;
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

  const OperatorModel({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    this.orgId,
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
  });

  factory OperatorModel.fromJson(Map<String, dynamic> json) {
    return OperatorModel(
      id: json['id'] as String,
      fullName: (json['full_name'] ?? '') as String,
      phoneNumber: (json['phone_number'] ?? '') as String,
      orgId: json['org_id'] as String?,
      companyId: (json['company_id'] ?? json['emp_code']) as String?,
      empCode: (json['emp_code'] ?? json['company_id']) as String?,
      biometricId: json['biometric_id'] as String?,
      bmrclId: json['bmrcl_id'] as String?,
      fatherName: json['father_name'] as String?,
      doj: json['doj'] as String?,
      esiNo: json['esi_no'] as String?,
      uanNo: json['uan_no'] as String?,
      isFaceRegistered:
          json['face_embedding'] != null || json['is_face_registered'] == true,
      weekOffs: (json['week_offs'] as num?)?.toInt() ?? 0,
    );
  }

  // Accepts map + optional named weekOffs passed by staff_repository.dart
  factory OperatorModel.fromMap(Map<String, dynamic> map, {int? weekOffs}) {
    return OperatorModel(
      id: map['id'] as String,
      fullName: (map['full_name'] ?? '') as String,
      phoneNumber: (map['phone_number'] ?? '') as String,
      orgId: map['org_id'] as String?,
      companyId: (map['company_id'] ?? map['emp_code']) as String?,
      empCode: (map['emp_code'] ?? map['company_id']) as String?,
      biometricId: map['biometric_id'] as String?,
      bmrclId: map['bmrcl_id'] as String?,
      fatherName: map['father_name'] as String?,
      doj: map['doj'] as String?,
      esiNo: map['esi_no'] as String?,
      uanNo: map['uan_no'] as String?,
      isFaceRegistered:
          map['face_embedding'] != null || map['is_face_registered'] == true,
      weekOffs: weekOffs ?? ((map['week_offs'] as num?)?.toInt() ?? 0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'phone_number': phoneNumber,
      'org_id': orgId,
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
    };
  }

  Map<String, dynamic> toMap() => toJson();
}
