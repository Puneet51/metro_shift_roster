class AttendanceSummaryModel {
  final int totalDuty;
  final double earnings;
  final int otDutyCount;
  final int weekOffCount;
  final int absentCount;

  const AttendanceSummaryModel({
    this.totalDuty = 0,
    this.earnings = 0.0,
    this.otDutyCount = 0,
    this.weekOffCount = 0,
    this.absentCount = 0,
  });
}
