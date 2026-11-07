import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/order.dart';
import '../widgets/common.dart';

class MainPrimeSettings extends StatefulWidget {
  const MainPrimeSettings({super.key});

  @override
  State<MainPrimeSettings> createState() => _MainPrimeSettingsState();
}

class _MainPrimeSettingsState extends State<MainPrimeSettings> {
  final username = TextEditingController();
  final password = TextEditingController();
  final form = GlobalKey<FormState>();
  MainPrimeAccount account = const MainPrimeAccount();
  bool started = false, loading = true, saving = false;
  String? loadError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      load();
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      final value = await AppScope.of(context).orders.mainPrimeAccount();
      if (!mounted) return;
      setState(() {
        account = value;
        username.text = value.username;
      });
    } catch (_) {
      if (mounted) {
        setState(() => loadError = 'تعذر تحميل حساب برايم. أعد المحاولة.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final login = username.text.trim();
      await AppScope.of(context).orders.saveMainPrimeAccount(
        login,
        password: password.text.isEmpty ? null : password.text,
      );
      if (!mounted) return;
      setState(() {
        account = MainPrimeAccount(
          username: login,
          configured: login.isNotEmpty,
        );
        username.text = login;
        password.clear();
      });
      showNotice(context, 'تم حفظ حساب برايم للحساب الرئيسي');
    } catch (e) {
      if (mounted) {
        showNotice(
          context,
          e is OrderException
              ? e.message
              : 'تعذر حفظ حساب برايم. حاول مرة ثانية.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'حساب برايم للحساب الرئيسي',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'يُستخدم للطلبات التي ينشئها getoge@gmail.com. لكل موظف حساب برايم الخاص به.',
        ),
        const SizedBox(height: 12),
        if (loading) const LinearProgressIndicator(),
        if (loadError != null) ...[
          Text(loadError!),
          TextButton(
            onPressed: loading ? null : load,
            child: const Text('إعادة المحاولة'),
          ),
        ],
        Text(
          account.configured ? 'حساب برايم محفوظ' : 'لم يُضف حساب برايم بعد',
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: username,
          enabled: !loading && !saving && loadError == null,
          maxLength: 254,
          textDirection: TextDirection.ltr,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'اسم المستخدم في برايم',
            helperText: 'امسح اسم المستخدم واحفظ لإزالة الحساب',
          ),
          validator: (value) =>
              (value?.trim().isEmpty ?? true) && password.text.isNotEmpty
              ? 'أدخل اسم المستخدم في برايم'
              : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: password,
          enabled: !loading && !saving && loadError == null,
          maxLength: 256,
          obscureText: true,
          textDirection: TextDirection.ltr,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'كلمة مرور برايم',
            helperText: account.configured
                ? 'اتركها فارغة للاحتفاظ بكلمة المرور الحالية'
                : 'مطلوبة لرفع الطلبات إلى برايم',
          ),
          validator: (value) =>
              username.text.trim().isNotEmpty &&
                  (!account.configured ||
                      username.text.trim() != account.username) &&
                  (value?.isEmpty ?? true)
              ? 'أدخل كلمة مرور برايم'
              : null,
        ),
        const Text('يُختار أول متجر وأول منتج من برايم تلقائياً.'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: loading || saving || loadError != null ? null : save,
          child: Text(saving ? 'جاري الحفظ…' : 'حفظ حساب برايم'),
        ),
      ],
    ),
  );
}
