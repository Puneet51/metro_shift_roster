import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metro_shift_roster/core/network/supabase_client.dart';
import 'package:metro_shift_roster/features/auth/presentation/auth_provider.dart';

final notificationsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final user = ref.watch(authNotifierProvider).user;
  if (user == null) return [];

  final res = await SupabaseService.client
      .from('notifications')
      .select()
      .eq('user_id', user.id)
      .order('created_at', ascending: false);

  return (res as List<dynamic>).map((e) => e as Map<String, dynamic>).toList();
});

class NotificationScreen extends ConsumerWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications & Alerts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            tooltip: 'Mark all as read',
            onPressed: () async {
              final user = ref.read(authNotifierProvider).user;
              if (user != null) {
                await SupabaseService.client
                    .from('notifications')
                    .update({'is_read': true}).eq('user_id', user.id);
                ref.invalidate(notificationsProvider);
              }
            },
          ),
        ],
      ),
      body: listAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No notifications yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, idx) {
              final item = items[idx];
              final isRead = item['is_read'] == true;
              final isOt = item['type'] == 'shift_alert' &&
                  (item['metadata']?['is_ot'] == true);

              return ListTile(
                tileColor: isRead
                    ? Colors.transparent
                    : Colors.blue.shade50.withOpacity(0.5),
                leading: CircleAvatar(
                  backgroundColor:
                      isOt ? Colors.purple : const Color(0xFF1E3A8A),
                  child: Icon(
                    isOt ? Icons.stars_rounded : Icons.subway_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                title: Text(
                  item['title'] ?? 'Alert',
                  style: TextStyle(
                      fontWeight: isRead ? FontWeight.normal : FontWeight.bold),
                ),
                subtitle: Text(item['body'] ?? '',
                    style: const TextStyle(fontSize: 13)),
                trailing: Text(
                  item['created_at'] != null
                      ? item['created_at'].toString().substring(0, 10)
                      : '',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                onTap: () async {
                  if (!isRead) {
                    await SupabaseService.client
                        .from('notifications')
                        .update({'is_read': true}).eq('id', item['id']);
                    ref.invalidate(notificationsProvider);
                  }
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading alerts: $e')),
      ),
    );
  }
}
