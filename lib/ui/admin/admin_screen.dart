import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../config.dart';
import '../../models/catalog.dart';
import '../../services/admin_service.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'catalog_editor.dart';
import 'order_management.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key, this.section = 'products'});
  final String section;
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final email = TextEditingController(),
      password = TextEditingController(),
      search = TextEditingController();
  final form = GlobalKey<FormState>();
  StreamSubscription<dynamic>? authSubscription;
  CatalogAdmin? admin;
  bool initialized = false,
      checking = true,
      allowed = false,
      busy = false,
      loading = false,
      more = false;
  String? error;
  List<Category> categories = [];
  List<Tattoo> products = [];
  int generation = 0, offset = 0;
  Timer? debounce;
  bool get isCategories => widget.section == 'categories';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (initialized) return;
    initialized = true;
    admin = AppScope.of(context).admin;
    authSubscription = admin?.authChanges.listen((_) => check());
    check();
  }

  Future<void> check() async {
    try {
      final ok = await admin?.isAdmin() ?? false;
      if (!mounted) return;
      setState(() {
        allowed = ok;
        checking = false;
      });
      if (ok) await load();
    } catch (_) {
      if (mounted) {
        setState(() {
          checking = false;
          error = 'تعذر التحقق من الحساب. حاول مرة ثانية.';
        });
      }
    }
  }

  Future<void> login() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await admin!.signIn(email.text, password.text);
      password.clear();
      await check();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is CatalogInputException
              ? e.message
              : 'تعذر تسجيل الدخول. تأكد من الحساب وكلمة المرور.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  Future<void> load({bool next = false}) async {
    if (!['products', 'categories'].contains(widget.section)) return;
    if (next && loading) return;
    final token = ++generation;
    if (!next) offset = 0;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repo = AppScope.of(context).catalog;
      final cats = await repo.categories(admin: true);
      final page = isCategories
          ? <Tattoo>[]
          : await repo.products(
              CatalogQuery(admin: true, offset: offset, search: search.text),
            );
      if (!mounted || token != generation) return;
      setState(() {
        categories = cats;
        products = next ? [...products, ...page] : page;
        offset += page.length;
        more = page.length == AppConfig.pageSize;
      });
    } catch (_) {
      if (mounted && token == generation) {
        setState(() {
          error = 'تعذر تحميل البيانات. حاول مرة ثانية.';
        });
      }
    } finally {
      if (mounted && token == generation) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> edit({Tattoo? product, Category? category}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CatalogEditor(
        admin: admin!,
        categories: categories,
        isCategory: isCategories,
        product: product,
        category: category,
        onSaved: load,
      ),
    );
  }

  @override
  void dispose() {
    generation++;
    authSubscription?.cancel();
    debounce?.cancel();
    email.dispose();
    password.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Row(
        children: [
          Brand(),
          SizedBox(width: 14),
          Text('إدارة G2G', style: TextStyle(fontSize: 18)),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'عرض الموقع',
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.open_in_new),
        ),
        if (admin?.signedIn ?? false)
          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed: () async {
              await admin!.signOut();
              if (mounted) {
                setState(() {
                  allowed = false;
                });
              }
            },
            icon: const Icon(Icons.logout),
          ),
      ],
    ),
    body: checking
        ? const Center(child: CircularProgressIndicator())
        : !allowed
        ? loginView()
        : managementView(),
  );
  Widget loginView() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(26),
        child: StudioPanel(
          padding: const EdgeInsets.all(28),
          child: Form(
            key: form,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(
                    child: CircleAvatar(
                      radius: 32,
                      backgroundColor: sage,
                      child: Icon(Icons.lock_outline, size: 26, color: forest),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'تسجيل دخول الإدارة',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'مساحتك لترتيب التصاميم وإدارة مجموعات G2G.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  if (admin == null)
                    const Text(
                      'أضف إعدادات Supabase عند تشغيل المشروع حتى تقدر تدير الكتالوج.',
                    ),
                  TextFormField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    validator: (v) =>
                        v != null && v.contains('@') ? null : 'أدخل بريد صحيح',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: password,
                    obscureText: true,
                    textDirection: TextDirection.ltr,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(
                      labelText: 'كلمة المرور',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    validator: (v) =>
                        v?.isNotEmpty ?? false ? null : 'أدخل كلمة المرور',
                    onFieldSubmitted: (_) {
                      if (!busy && admin != null) login();
                    },
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy || admin == null ? null : login,
                    child: Text(busy ? 'جاري الدخول…' : 'دخول'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Widget managementView() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1100),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  for (final entry in const {
                    'products': 'المنتجات',
                    'categories': 'التصنيفات',
                    'orders': 'الطلبات',
                    'team': 'الموظفون',
                    'settings': 'التوصيل',
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(entry.value),
                        selected: widget.section == entry.key,
                        onSelected: (_) => context.go('/admin/${entry.key}'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!['products', 'categories'].contains(widget.section))
            Expanded(
              child: OrderManagement(
                key: ValueKey(widget.section),
                section: widget.section,
              ),
            )
          else ...[
            if (AppConfig.useTestData)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  'وضع التجربة: التغييرات مؤقتة وتنحذف عند إعادة تحميل الصفحة.',
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'G2G / STUDIO',
                          style: TextStyle(
                            color: clay,
                            fontSize: 10,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          isCategories ? 'مجموعاتك' : 'مساحة التصاميم',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: sage,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isCategories
                          ? '${categories.length} تصنيف'
                          : '${products.length}${more ? '+' : ''} تصميم',
                      style: const TextStyle(color: forest, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: isCategories ? 'إضافة تصنيف' : 'إضافة وشم',
                      child: FilledButton.icon(
                        onPressed: () => edit(),
                        icon: const Icon(Icons.add),
                        label: Text(isCategories ? 'إضافة تصنيف' : 'إضافة وشم'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!isCategories)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: search,
                  decoration: const InputDecoration(
                    hintText: 'ابحث عن وشم أو رقم التصميم',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) {
                    debounce?.cancel();
                    debounce = Timer(const Duration(milliseconds: 300), load);
                  },
                ),
              ),
            if (loading) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(child: Text(error!)),
                    TextButton(
                      onPressed: load,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: isCategories
                  ? ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: categories.length,
                      itemBuilder: (context, i) {
                        final c = categories[i];
                        return Card(
                          color: Colors.white,
                          child: ListTile(
                            leading: SizedBox(
                              width: 54,
                              height: 54,
                              child: CatalogImage(c.imageUrl, padding: 2),
                            ),
                            title: Text(c.name),
                            subtitle: Text(
                              '${c.active ? 'ظاهر' : 'مخفي'} • الترتيب ${c.sortOrder}',
                            ),
                            onTap: () => edit(category: c),
                            trailing: IconButton(
                              tooltip: 'حذف القسم',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                if (!await confirm(
                                  context,
                                  'حذف القسم؟',
                                  'تقدر تحذفه فقط إذا ما بيه وشومات.',
                                )) {
                                  return;
                                }
                                try {
                                  await admin!.deleteCategory(c.id);
                                  await load();
                                } catch (e) {
                                  if (context.mounted) {
                                    showNotice(
                                      context,
                                      e is CatalogInputException
                                          ? e.message
                                          : 'تعذر الحذف',
                                    );
                                  }
                                }
                              },
                            ),
                          ),
                        );
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: products.length + 1,
                      itemBuilder: (context, i) {
                        if (i == products.length) {
                          if (more) {
                            return OutlinedButton(
                              onPressed: loading
                                  ? null
                                  : () => load(next: true),
                              child: const Text('عرض المزيد'),
                            );
                          }
                          if (products.isEmpty && !loading && error == null) {
                            return const MessagePanel(
                              title: 'أضف أول وشم للكتالوج',
                            );
                          }
                          return const SizedBox(height: 24);
                        }
                        final p = products[i];
                        return Card(
                          color: Colors.white,
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(10),
                            leading: SizedBox(
                              width: 66,
                              height: 66,
                              child: CatalogImage(p.thumbnail, padding: 3),
                            ),
                            title: Text(
                              p.displayName,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            subtitle: Text(
                              [
                                p.code,
                                p.active ? 'ظاهر' : 'مخفي',
                                p.formattedPrice,
                              ].where((v) => v.isNotEmpty).join(' • '),
                            ),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: () => edit(product: p),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    ),
  );
}
