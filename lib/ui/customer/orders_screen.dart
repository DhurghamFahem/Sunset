import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/order.dart';
import '../order_screen.dart';

class CustomerOrdersScreen extends StatefulWidget {
  const CustomerOrdersScreen({super.key});
  @override
  State<CustomerOrdersScreen> createState() => _CustomerOrdersScreenState();
}

class _CustomerOrdersScreenState extends State<CustomerOrdersScreen> {
  late Future<List<({TattooOrder? order, String token})>> future;
  bool started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      future = load();
    }
  }

  Future<List<({TattooOrder? order, String token})>> load() async {
    final app = AppScope.of(context);
    return Future.wait(
      app.selection.savedOrders.map((entry) async {
        try {
          return (
            order: await app.orders.get(entry.id, token: entry.token),
            token: entry.token,
          );
        } catch (_) {
          return (order: null, token: entry.token);
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('طلباتي'),
      actions: [
        IconButton(
          onPressed: () => setState(() => future = load()),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'طلبات هذا الجهاز. احتفظ برمز الطلب للتواصل معنا. مسح بيانات المتصفح يزيل وصولك المحلي للطلبات.',
            ),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              const Text(
                'لا توجد طلبات بعد. اختر وشوماتك وجهّز صورها لإنشاء طلب.',
              ),
            for (final row in rows)
              row.order == null
                  ? const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'تعذر تحميل طلب محفوظ. أعد المحاولة. طلبات وضع التجربة تُحذف عند إعادة تحميل التطبيق.',
                        ),
                      ),
                    )
                  : Card(
                      child: ListTile(
                        title: Text(row.order!.code),
                        subtitle: Text(row.order!.status.label),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => OrderScreen(
                                order: row.order!,
                                token: row.token,
                              ),
                            ),
                          );
                          if (mounted) setState(() => future = load());
                        },
                      ),
                    ),
          ],
        );
      },
    ),
  );
}
