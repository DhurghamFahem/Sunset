import '../config.dart';
import 'catalog.dart';

class TattooOffer {
  const TattooOffer({
    required this.id,
    required this.name,
    required this.price,
    required this.products,
    this.active = true,
    this.publicVisible = true,
  });

  final String id, name;
  final int price;
  final List<Tattoo> products;
  final bool active, publicVisible;
  String get formattedPrice => AppConfig.money(price);

  factory TattooOffer.fromJson(Json json) => TattooOffer(
    id: json['id'] as String,
    name: json['name_ar'] as String,
    price: json['price'] as int,
    active: json['active'] as bool,
    publicVisible: json['public_visible'] as bool,
    products: List.unmodifiable(
      (json['products'] as List).map(
        (p) => Tattoo.fromJson(Map<String, dynamic>.from(p as Map)),
      ),
    ),
  );
}
