class UserModel {
  final String id;
  final String? orgId;
  final String fullName;
  final String phone;
  final String role; // 'operator', 'supervisor', 'admin'
  final bool hasPinConfigured;
  final String? empCode;
  final String? biometricId;
  final String? fatherName;
  final String? doj;
  final String? esiNo;
  final String? uanNo;
  final String? faceEmbedding;
  final String? fcmToken;
  final String? parentSupervisorId;
  final bool isReliever;

  const UserModel({
    required this.id,
    this.orgId,
    required this.fullName,
    required this.phone,
    required this.role,
    this.hasPinConfigured = false,
    this.empCode,
    this.biometricId,
    this.fatherName,
    this.doj,
    this.esiNo,
    this.uanNo,
    this.faceEmbedding,
    this.fcmToken,
    this.parentSupervisorId,
    this.isReliever = false,
  });

  /// Returns the primary supervisor ID that owns this user's scope.
  ///
  /// A reliever has role == 'supervisor', but is still subordinate to the
  /// primary supervisor in parentSupervisorId. Therefore relievers must be
  /// resolved before the generic supervisor case.
  ///
  /// Scope:
  /// - admin -> own ID
  /// - primary supervisor -> own ID
  /// - reliever -> parent supervisor ID
  /// - operator -> parent supervisor ID
  String get effectiveSupervisorId {
    if (role == 'admin') {
      return id;
    }

    if (role == 'supervisor' &&
        isReliever &&
        parentSupervisorId != null &&
        parentSupervisorId!.isNotEmpty) {
      return parentSupervisorId!;
    }

    if (role == 'supervisor') {
      return id;
    }

    if (parentSupervisorId != null && parentSupervisorId!.isNotEmpty) {
      return parentSupervisorId!;
    }

    return id;
  }

  // Aliases for compatibility across screens
  String? get companyId => empCode;
  String? get bmrclId => biometricId;
  String get phoneNumber => phone;
  bool get isFaceRegistered =>
      faceEmbedding != null && faceEmbedding!.trim().isNotEmpty;

  UserModel copyWith({
    String? id,
    String? orgId,
    String? fullName,
    String? phone,
    String? role,
    bool? hasPinConfigured,
    String? empCode,
    String? biometricId,
    String? fatherName,
    String? doj,
    String? esiNo,
    String? uanNo,
    String? faceEmbedding,
    String? fcmToken,
    String? parentSupervisorId,
    bool? isReliever,
    bool? isFaceRegistered,
  }) {
    return UserModel(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      role: role ?? this.role,
      hasPinConfigured: hasPinConfigured ?? this.hasPinConfigured,
      empCode: empCode ?? this.empCode,
      biometricId: biometricId ?? this.biometricId,
      fatherName: fatherName ?? this.fatherName,
      doj: doj ?? this.doj,
      esiNo: esiNo ?? this.esiNo,
      uanNo: uanNo ?? this.uanNo,
      faceEmbedding: (isFaceRegistered == false)
          ? null
          : (faceEmbedding ??
                (isFaceRegistered == true ? 'enrolled' : this.faceEmbedding)),
      fcmToken: fcmToken ?? this.fcmToken,
      parentSupervisorId: parentSupervisorId ?? this.parentSupervisorId,
      isReliever: isReliever ?? this.isReliever,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'org_id': orgId,
      'full_name': fullName,
      'phone': phone,
      'role': role,
      'has_pin_configured': hasPinConfigured,
      'emp_code': empCode,
      'biometric_id': biometricId,
      'father_name': fatherName,
      'doj': doj,
      'esi_no': esiNo,
      'uan_no': uanNo,
      'face_embedding': faceEmbedding,
      'fcm_token': fcmToken,
      'parent_supervisor_id': parentSupervisorId,
      'is_reliever': isReliever,
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id']?.toString() ?? '',
      orgId: map['org_id']?.toString(),
      fullName: map['full_name']?.toString() ?? '',
      phone: (map['phone'] ?? map['phone_number'])?.toString() ?? '',
      role: map['role']?.toString() ?? 'operator',
      hasPinConfigured:
          map['has_pin_configured'] as bool? ??
          (map['pin_hash'] != null && map['pin_hash'].toString().isNotEmpty),
      empCode: (map['emp_code'] ?? map['company_id'])?.toString(),
      biometricId: (map['biometric_id'] ?? map['bmrcl_id'])?.toString(),
      fatherName: map['father_name']?.toString(),
      doj: map['doj']?.toString(),
      esiNo: map['esi_no']?.toString(),
      uanNo: map['uan_no']?.toString(),
      faceEmbedding: map['face_embedding']?.toString(),
      fcmToken: map['fcm_token']?.toString(),
      parentSupervisorId: map['parent_supervisor_id']?.toString(),
      isReliever: map['is_reliever'] == true || map['is_reliever'] == 'true',
    );
  }
}
