import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/catalog.dart';
import '../../models/catalog_search.dart';
import '../../services/admin_service.dart';
import '../widgets/common.dart';
import '../theme.dart';

class CatalogEditor extends StatefulWidget {
  const CatalogEditor({
    super.key,
    required this.admin,
    required this.categories,
    required this.isCategory,
    required this.onSaved,
    this.product,
    this.category,
  });
  final AdminService admin;
  final List<Category> categories;
  final bool isCategory;
  final Tattoo? product;
  final Category? category;
  final Future<void> Function() onSaved;
  @override
  State<CatalogEditor> createState() => _CatalogEditorState();
}

class _CatalogEditorState extends State<CatalogEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name,
      code,
      width,
      height,
      price,
      order,
      tags;
  late bool active, featured, isNew;
  String? categoryImageUrl, editingId, error;
  late List<TattooImage> images;
  String? get imageUrl =>
      widget.isCategory ? categoryImageUrl : images.firstOrNull?.url;
  String? get thumbnailUrl => images.firstOrNull?.thumbnailUrl;
  late Set<String> categoryIds;
  late Set<TattooAudience> audiences;
  late Set<BodyPlacement> bodyPlacements;
  final staged = <String, UploadedImage>{};
  bool busy = false, uploading = false;
  @override
  void initState() {
    super.initState();
    final p = widget.product, c = widget.category;
    editingId = widget.isCategory ? c?.id : p?.id;
    name = TextEditingController(text: widget.isCategory ? c?.name : p?.name);
    code = TextEditingController(text: p?.code);
    tags = TextEditingController(text: p?.tags.join('، ') ?? '');
    width = TextEditingController(text: p?.width?.toString() ?? '');
    height = TextEditingController(text: p?.height?.toString() ?? '');
    price = TextEditingController(text: p?.price?.toString() ?? '');
    order = TextEditingController(
      text: '${widget.isCategory ? c?.sortOrder ?? 0 : p?.sortOrder ?? 0}',
    );
    active = widget.isCategory ? c?.active ?? true : p?.active ?? true;
    featured = p?.featured ?? false;
    isNew = p?.isNew ?? false;
    categoryIds = p?.categoryIds.toSet() ?? {};
    audiences = p?.audiences.toSet() ?? {};
    bodyPlacements = p?.bodyPlacements.toSet() ?? {};
    categoryImageUrl = c?.imageUrl;
    images = p?.images.toList() ?? [];
  }

  @override
  void dispose() {
    for (final c in [name, code, width, height, price, order, tags]) {
      c.dispose();
    }
    for (final upload in staged.values) {
      unawaited(widget.admin.discard(upload.objects));
    }
    super.dispose();
  }

  Future<void> upload() async {
    setState(() {
      uploading = true;
      error = null;
    });
    try {
      final result = await widget.admin.pickAndUpload(
        category: widget.isCategory,
      );
      if (result == null) return;
      if (!mounted) {
        await widget.admin.discard(result.objects);
        return;
      }
      if (widget.isCategory) {
        for (final upload in staged.values) {
          await widget.admin.discard(upload.objects);
        }
        staged.clear();
        if (!mounted) {
          await widget.admin.discard(result.objects);
          return;
        }
      }
      setState(() {
        staged[result.imageUrl] = result;
        if (widget.isCategory) {
          categoryImageUrl = result.imageUrl;
        } else {
          images.add(
            TattooImage(
              url: result.imageUrl,
              thumbnailUrl: result.thumbnailUrl,
            ),
          );
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is CatalogInputException
              ? e.message
              : 'تعذر رفع الصورة. تأكد من الاتصال وحاول مرة ثانية.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          uploading = false;
        });
      }
    }
  }

  void removeImage(int index) {
    final image = images[index];
    setState(() => images.removeAt(index));
    final upload = staged.remove(image.url);
    if (upload != null) unawaited(widget.admin.discard(upload.objects));
  }

  Future<void> save({bool another = false}) async {
    if (!form.currentState!.validate()) return;
    if (!widget.isCategory && imageUrl == null) {
      setState(() {
        error = 'ارفع صورة الوشم أولاً.';
      });
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final Json data = {
        'name_ar': name.text.trim().isEmpty ? null : name.text.trim(),
        'image_url': imageUrl,
        'active': active,
        'sort_order': int.parse(order.text),
      };
      if (!widget.isCategory) {
        data.addAll({
          'code': code.text.trim().toUpperCase(),
          'tags': parseCatalogTags(tags.text),
          'category_ids': categoryIds.toList(),
          'audiences': audiences.map((value) => value.name).toList(),
          'body_placements': bodyPlacements.map((value) => value.name).toList(),
          'thumbnail_url': thumbnailUrl,
          'additional_images': images
              .skip(1)
              .map((image) => image.toJson())
              .toList(),
          'width_cm': double.tryParse(width.text),
          'height_cm': double.tryParse(height.text),
          'price': int.tryParse(price.text),
          'featured': featured,
          'is_new': isNew,
        });
      }
      await widget.admin.save(
        widget.isCategory ? 'categories' : 'products',
        data,
        id: editingId,
      );
      staged.clear();
      await widget.onSaved();
      if (!mounted) return;
      if (another) {
        setState(() {
          editingId = null;
          code.clear();
          name.clear();
          tags.clear();
          images.clear();
          categoryImageUrl = null;
          active = true;
          featured = false;
          isNew = false;
          order.text = '0';
        });
        showNotice(context, 'تم الحفظ. أضف الوشم التالي.');
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e is CatalogInputException
              ? e.message
              : 'تعذر الحفظ. حاول مرة ثانية.';
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

  String? positive(String? v) {
    if (v == null || v.isEmpty) return 'أدخل القياس بالسنتيمتر';
    final n = double.tryParse(v);
    return n != null && n.isFinite && n > 0 && n < 1000000
        ? null
        : 'أدخل قياس صحيح أكبر من صفر';
  }

  Widget multiSelect<T>(
    String label,
    Map<T, String> options,
    Set<T> selected,
  ) => FormField<Set<T>>(
    validator: (_) => selected.isEmpty ? 'اختار خيار واحد على الأقل' : null,
    builder: (field) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: options.entries
                .map(
                  (entry) => FilterChip(
                    label: Text(entry.value),
                    selected: selected.contains(entry.key),
                    onSelected: busy || uploading
                        ? null
                        : (checked) {
                            setState(() {
                              checked
                                  ? selected.add(entry.key)
                                  : selected.remove(entry.key);
                            });
                            field.didChange(selected);
                          },
                  ),
                )
                .toList(),
          ),
          if (field.hasError)
            Text(
              field.errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );

  Widget _section(String number, String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 16),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: sage,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            number,
            style: const TextStyle(fontSize: 11, color: forest),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !uploading,
    child: Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.isCategory
                                  ? 'بيانات التصنيف'
                                  : 'بيانات الوشم',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'إغلاق',
                            onPressed: busy || uploading
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'رتّب التفاصيل، وخلي تصميمك جاهز للاكتشاف.',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                      _section('01', 'الصور'),
                      if (widget.isCategory && imageUrl != null)
                        SizedBox(
                          height: 150,
                          child: CatalogImage(imageUrl, label: 'معاينة الصورة'),
                        ),
                      if (!widget.isCategory && images.isNotEmpty) ...[
                        const Text(
                          'صور الوشم • الصورة الأولى تظهر بالكتالوج والاختيارات',
                        ),
                        const SizedBox(height: 8),
                        for (var index = 0; index < images.length; index++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 72,
                                  height: 72,
                                  child: CatalogImage(
                                    images[index].thumbnail,
                                    padding: 4,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    index == 0
                                        ? 'الصورة الرئيسية'
                                        : 'صورة ${index + 1}',
                                  ),
                                ),
                                if (index > 0)
                                  IconButton(
                                    tooltip:
                                        'تعيين الصورة ${index + 1} كرئيسية',
                                    onPressed: busy || uploading
                                        ? null
                                        : () => setState(() {
                                            images.insert(
                                              0,
                                              images.removeAt(index),
                                            );
                                          }),
                                    icon: const Icon(Icons.star_outline),
                                  ),
                                IconButton(
                                  tooltip: 'حذف الصورة ${index + 1}',
                                  onPressed: busy || uploading
                                      ? null
                                      : () => removeImage(index),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: busy || uploading ? null : upload,
                        icon: const Icon(Icons.upload_outlined),
                        label: Text(
                          uploading
                              ? 'جاري رفع الصورة…'
                              : widget.isCategory
                              ? 'رفع صورة PNG / JPG / WebP'
                              : 'إضافة صورة PNG / JPG / WebP',
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'حتى 10 ميغابايت لكل صورة • نحافظ على الصور الأصلية',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 18),
                      _section(
                        '02',
                        widget.isCategory
                            ? 'معلومات التصنيف'
                            : 'معلومات التصميم',
                      ),
                      if (!widget.isCategory) ...[
                        TextFormField(
                          controller: code,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                            labelText: 'كود الوشم (للإدارة)',
                            hintText: 'G2G-001',
                          ),
                          validator: (v) =>
                              RegExp(r'^G2G-[0-9]{3,}$')
                                  .hasMatch((v ?? '').trim().toUpperCase())
                              ? null
                              : 'مثال: G2G-001',
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: name,
                        maxLength: widget.isCategory ? 120 : 160,
                        decoration: InputDecoration(
                          labelText: widget.isCategory
                              ? 'اسم التصنيف بالعربي'
                              : 'اسم الوشم الظاهر للزبون',
                        ),
                        validator: (v) => (v?.trim().isEmpty ?? true)
                            ? (widget.isCategory
                                  ? 'أدخل اسم التصنيف'
                                  : 'أدخل اسم الوشم')
                            : null,
                      ),
                      if (!widget.isCategory) ...[
                        _section('03', 'التصنيف والظهور في البحث'),
                        multiSelect('مناسب لـ (ممكن تختار الاثنين)', {
                          for (final value in TattooAudience.values)
                            value: value.label,
                        }, audiences),
                        multiSelect('أماكن الوشم (ممكن تختار أكثر من مكان)', {
                          for (final value in BodyPlacement.values)
                            value: value.label,
                        }, bodyPlacements),
                        multiSelect('التصنيفات (ممكن تختار أكثر من تصنيف)', {
                          for (final category in widget.categories)
                            category.id: category.name,
                        }, categoryIds),
                        if (widget.categories.isEmpty)
                          const Text('أضف تصنيف أولاً حتى تقدر تحفظ الوشم.'),
                        TextFormField(
                          controller: tags,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'وسوم البحث',
                            hintText: 'وردة، ناعم، طبيعة، floral',
                            helperText: 'افصل الوسوم بفاصلة. أضف مرادفات وكلمات عربي وإنكليزي.',
                            helperMaxLines: 2,
                          ),
                          validator: (value) {
                            final parsed = parseCatalogTags(value ?? '');
                            return parsed.length > 30 ||
                                    parsed.any((tag) => tag.runes.length > 64)
                                ? 'حتى 30 وسم، وكل وسم بحد أقصى 64 حرف'
                                : null;
                          },
                        ),
                        const SizedBox(height: 14),
                        _section('04', 'القياس والسعر'),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: width,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'العرض (سم)',
                                ),
                                validator: positive,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextFormField(
                                controller: height,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'الارتفاع (سم)',
                                ),
                                validator: positive,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: price,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'السعر بالدينار (اختياري)',
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return null;
                            final n = int.tryParse(v);
                            return n != null && n >= 0 && n <= 2147483647
                                ? null
                                : 'أدخل سعر صحيح';
                          },
                        ),
                        const SizedBox(height: 14),
                      ],
                      _section(
                        widget.isCategory ? '03' : '05',
                        'إعدادات العرض',
                      ),
                      TextFormField(
                        controller: order,
                        keyboardType: const TextInputType.numberWithOptions(
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'الترتيب (الأصغر يظهر أولاً)',
                        ),
                        validator: (v) => int.tryParse(v ?? '') == null
                            ? 'أدخل رقم صحيح'
                            : null,
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('ظاهر بالكتالوج'),
                        value: active,
                        onChanged: (v) => setState(() {
                          active = v;
                        }),
                      ),
                      if (!widget.isCategory) ...[
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('مميز'),
                          value: featured,
                          onChanged: (v) => setState(() {
                            featured = v;
                          }),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('وصل حديثاً'),
                          value: isNew,
                          onChanged: (v) => setState(() {
                            isNew = v;
                          }),
                        ),
                      ],
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton(
                      onPressed: busy || uploading ? null : save,
                      child: Text(busy ? 'جاري الحفظ…' : 'حفظ'),
                    ),
                    if (!widget.isCategory)
                      TextButton(
                        onPressed: busy || uploading
                            ? null
                            : () => save(another: true),
                        child: const Text('حفظ وإضافة وشم آخر'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
