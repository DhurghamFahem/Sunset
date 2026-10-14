import 'package:flutter_test/flutter_test.dart';
import 'package:sunset/models/catalog.dart';
import 'package:sunset/repositories/offer_repository.dart';
import 'package:sunset/repositories/test_catalog_repository.dart';
import 'package:sunset/services/admin_service.dart';
import 'package:sunset/services/test_admin_service.dart';

void main() {
  late TestCatalogRepository catalog;
  late TestAdminService admin;
  late MemoryOfferRepository offers;
  late List<Tattoo> tattoos;
  setUp(() async {
    catalog = TestCatalogRepository();
    admin = TestAdminService(catalog);
    offers = MemoryOfferRepository(catalog, admin);
    await admin.signIn('test@gmail.com', '1234');
    tattoos = await catalog.products(const CatalogQuery(admin: true));
  });
  tearDown(() => admin.dispose());

  Future<void> save(List<String> ids, {int price = 7500, bool active = true}) =>
      offers.save(
        id: 'offer',
        name: 'عرض الورود',
        price: price,
        productIds: ids,
        active: active,
      );

  test(
    'single tattoo, multiple tattoos, edit, retry, delete preserve originals',
    () async {
      await save([tattoos[0].id]);
      expect((await offers.list()).single.products.single.id, tattoos[0].id);
      await save([tattoos[1].id, tattoos[0].id]);
      await save([tattoos[1].id, tattoos[0].id]);
      final offer = (await offers.list()).single;
      expect(offer.products.map((p) => p.id), [tattoos[1].id, tattoos[0].id]);
      expect(offer.price, 7500);
      expect((await catalog.product(tattoos[0].id))!.price, tattoos[0].price);
      expect(
        () => catalog.deleteTattoo(tattoos[0].id),
        throwsA(isA<CatalogInputException>()),
      );
      await offers.delete('offer');
      expect(await offers.list(), isEmpty);
      expect(await catalog.product(tattoos[0].id), isNotNull);
      catalog.deleteTattoo(tattoos[0].id);
    },
  );

  test(
    'hidden offers and any unavailable member hide the entire bundle',
    () async {
      await save([tattoos[0].id, tattoos[1].id], active: false);
      expect(await offers.list(), isEmpty);
      expect((await offers.list(admin: true)).single.active, isFalse);
      await save([tattoos[0].id, tattoos[1].id]);
      catalog.save('products', {
        ...tattoos[0].toJson(),
        'active': false,
      }, id: tattoos[0].id);
      expect(await offers.list(), isEmpty);
      expect((await offers.list(admin: true)).single.products, hasLength(2));
      catalog.save('products', tattoos[0].toJson(), id: tattoos[0].id);
      for (final category in await catalog.categories()) {
        catalog.save('categories', {
          'name_ar': category.name,
          'active': false,
        }, id: category.id);
      }
      expect(await offers.list(), isEmpty);
    },
  );

  test(
    'validates membership and price without changing a saved offer',
    () async {
      await save([tattoos[0].id], price: 0);
      for (final ids in [
        <String>[],
        ['missing'],
        [tattoos[0].id, tattoos[0].id],
      ]) {
        await expectLater(save(ids), throwsA(isA<CatalogInputException>()));
      }
      await expectLater(
        save([tattoos[0].id], price: -1),
        throwsA(isA<CatalogInputException>()),
      );
      await expectLater(
        save([tattoos[0].id], price: 2147483648),
        throwsA(isA<CatalogInputException>()),
      );
      expect((await offers.list()).single.price, 0);
    },
  );

  test('anonymous visitors can read public offers but cannot mutate or read admin list', () async {
    await save([tattoos[0].id]);
    await admin.signOut();
    expect(await offers.list(), hasLength(1));
    await expectLater(
      save([tattoos[0].id]),
      throwsA(isA<CatalogInputException>()),
    );
    await expectLater(
      offers.list(admin: true),
      throwsA(isA<CatalogInputException>()),
    );
    await expectLater(
      offers.delete('offer'),
      throwsA(isA<CatalogInputException>()),
    );
  });
}
