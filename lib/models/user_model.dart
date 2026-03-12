class UserModel {
  final int systemUserId;
  final String name;
  final String emailId;
  final String mobileNo;
  final String? referralCode;

  UserModel({
    required this.systemUserId,
    required this.name,
    required this.emailId,
    required this.mobileNo,
    this.referralCode,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      systemUserId: (json['system_user_id'] as num?)?.toInt() ?? 0,
      name: json['name']?.toString().trim() ?? '',
      emailId: json['email_id']?.toString() ?? '',
      mobileNo: json['mobile_no']?.toString() ?? '',
      referralCode: json['referral_code']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'system_user_id': systemUserId,
      'name': name,
      'email_id': emailId,
      'mobile_no': mobileNo,
      'referral_code': referralCode,
    };
  }
}
