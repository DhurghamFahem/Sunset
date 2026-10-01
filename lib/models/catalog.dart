import '../config.dart';

typedef Json = Map<String, dynamic>;

enum TattooAudience {
  men('رجالي'),
  women('نسائي');

  const TattooAudience(this.label);
  final String label;
}

enum BodyPlacement {
  arm('الذراع'),
  back('الظهر'),
  shoulder('الكتف'),
  wrist('المعصم'),
  hand('اليد'),
  chest('الصدر'),
  neck('الرقبة'),
  leg('الساق'),
  ankle('الكاحل'),
  foot('القدم');

  const BodyPlacement(this.label);
  final String label;
}

class Category {
  const Category({
    required this.id,
    required this.name,
    this.imageUrl,
    this.active = true,
    this.sortOrder = 0,
  });
  final String id, name;
  final String? imageUrl;
  final bool active;
  final int sortOrder;
  factory Category.fromJson(Json j) => Category(
    id: j['id'] as String,
    name: j['name_ar'] as String,
    imageUrl: j['image_url'] as String?,
    active: j['active'] as bool? ?? true,
    sortOrder: j['sort_order'] as int? ?? 0,
  );
}

class TattooImage {
  const TattooImage({required this.url, this.thumbnailUrl});
  final String url;
  final String? thumbnailUrl;
  String get thumbnail => thumbnailUrl ?? url;
  factory TattooImage.fromJson(Json json) => TattooImage(
    url: json['image_url'] as String,
    thumbnailUrl: json['thumbnail_url'] as String?,
  );
  Json toJson() => {'image_url': url, 'thumbnail_url': thumbnailUrl};
}

class Tattoo {
  const Tattoo({
    required this.id,
    required this.code,
    required this.imageUrl,
    this.name,
    this.categoryIds = const [],
    this.audiences = const [TattooAudience.men, TattooAudience.women],
    this.bodyPlacements = const [],
    this.thumbnailUrl,
    this.additionalImages = const [],
    this.width,
    this.height,
    this.price,
    this.active = true,
    this.featured = false,
    this.isNew = false,
    this.sortOrder = 0,
  });
  final String id, code, imageUrl;
  final String? name, thumbnailUrl;
  final List<TattooImage> additionalImages;
  List<TattooImage> get images => List.unmodifiable([
    TattooImage(url: imageUrl, thumbnailUrl: thumbnailUrl),
    ...additionalImages,
  ]);
  final List<String> categoryIds;
  final List<TattooAudience> audiences;
  final List<BodyPlacement> bodyPlacements;
  final double? width, height;
  final int? price;
  final bool active, featured, isNew;
  final int sortOrder;
  String get thumbnail => thumbnailUrl ?? imageUrl;
  String get dimensions => width == null || height == null
      ? ''
      : '${_n(width!)} × ${_n(height!)} سم';
  String get formattedPrice => price == null ? '' : AppConfig.money(price!);
  static String _n(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();
  factory Tattoo.fromJson(Json j) => Tattoo(
    id: j['id'] as String,
    code: j['code'] as String,
    imageUrl: j['image_url'] as String,
    thumbnailUrl: j['thumbnail_url'] as String?,
    additionalImages: List.unmodifiable(
      (j['additional_images'] as List? ?? []).map(
        (image) =>
            TattooImage.fromJson(Map<String, dynamic>.from(image as Map)),
      ),
    ),
    name: j['name_ar'] as String?,
    // Preserve selections saved before multi-category support.
    categoryIds: List<String>.unmodifiable(
      j['category_ids'] as List? ??
          [if (j['category_id'] != null) j['category_id']],
    ),
    audiences: List.unmodifiable(
      TattooAudience.values.where(
        (value) => (j['audiences'] as List?)?.contains(value.name) ?? true,
      ),
    ),
    bodyPlacements: List.unmodifiable(
      BodyPlacement.values.where(
        (value) =>
            (j['body_placements'] as List?)?.contains(value.name) ?? false,
      ),
    ),
    width: (j['width_cm'] as num?)?.toDouble(),
    height: (j['height_cm'] as num?)?.toDouble(),
    price: j['price'] as int?,
    active: j['active'] as bool? ?? true,
    featured: j['featured'] as bool? ?? false,
    isNew: j['is_new'] as bool? ?? false,
    sortOrder: j['sort_order'] as int? ?? 0,
  );
  Json toJson() => {
    'id': id,
    'code': code,
    'image_url': imageUrl,
    'thumbnail_url': thumbnailUrl,
    'additional_images': additionalImages
        .map((image) => image.toJson())
        .toList(),
    'name_ar': name,
    'category_ids': categoryIds,
    'audiences': audiences.map((value) => value.name).toList(),
    'body_placements': bodyPlacements.map((value) => value.name).toList(),
    'width_cm': width,
    'height_cm': height,
    'price': price,
    'active': active,
    'featured': featured,
    'is_new': isNew,
    'sort_order': sortOrder,
  };
}

enum CatalogSort { curated, newest, featured, price, size }

class CatalogQuery {
  const CatalogQuery({
    this.categoryId,
    this.audience,
    this.bodyPlacements = const [],
    this.search = '',
    this.sort = CatalogSort.curated,
    this.offset = 0,
    this.admin = false,
  });
  final String? categoryId;
  final TattooAudience? audience;
  final List<BodyPlacement> bodyPlacements;
  final String search;
  final CatalogSort sort;
  final int offset;
  final bool admin;
}
