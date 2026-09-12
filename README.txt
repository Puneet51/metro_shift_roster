METRO SHIFT ROSTER - FINAL ATTENDANCE PACKAGE

This package contains the updated lib/ folder plus the final database patch.
The original uploaded archive contained only lib/, so this is not a complete
Flutter project with pubspec.yaml/android/ios/etc.

ATTENDANCE RULES
- Current published assignment -> present.
- Never assigned -> absent.
- Previously assigned and removed before duty start -> week_off.
- week_off earnings -> 0.
- present earnings come from shifts.daily_amount; no amount is hard-coded.
- Excel displays present as P and absent/week_off as A.
- week_off remains a distinct DB status for metrics.

PUNCH REMOVAL
- Punch UI/integration has been removed from lib/.
- Attendance schema is punch-free in the current database.
- The SQL patch contains no punch-session or punch-column dependencies.

ASSIGNMENT HISTORY
- shift_assignment_history records inserted/removed assignment events.
- The trigger uses the database's allowed action values: inserted and removed.

VALIDATION COMPLETED
- Duplicate attendance rows were cleaned.
- Unique operator/date index was created.
- Assignment history trigger was tested for inserted + removed.
- A temporary assigned-then-removed test produced week_off with earnings 0.
