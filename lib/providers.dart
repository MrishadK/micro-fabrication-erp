import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database_helper.dart';

final navIndexProvider = StateProvider<int>((ref) => 0);
final searchQueryProvider = StateProvider<String>((ref) => "");

// ✅ 1. THE GLOBAL DB REFRESH TRIGGER
final dbRefreshTriggerProvider = StateProvider<int>((ref) => 0);

final activeJobsProvider = FutureProvider.autoDispose((ref) async {
  // ✅ 2. Watch the trigger. When it changes, this provider automatically re-runs.
  ref.watch(dbRefreshTriggerProvider);
  return await DatabaseHelper.instance.getActiveJobs();
});

final historyJobsProvider = FutureProvider.autoDispose((ref) async {
  // ✅ Watch the trigger
  ref.watch(dbRefreshTriggerProvider);
  final query = ref.watch(searchQueryProvider);
  return await DatabaseHelper.instance.getHistoryJobs(query);
});

// For the Client History Page
final clientHistoryProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      query,
    ) async {
      // ✅ Watch the trigger
      ref.watch(dbRefreshTriggerProvider);
      if (query.isEmpty) return [];
      return await DatabaseHelper.instance.getClientHistory(query);
    });

// (If you have topDebtorsProvider in this file too, update it like this):
final topDebtorsProvider = FutureProvider.autoDispose((ref) async {
  // ✅ Watch the trigger
  ref.watch(dbRefreshTriggerProvider);
  return await DatabaseHelper.instance.getTopDebtors();
});
