# G2G — Arabic herbal tattoo catalog

A mobile-first Flutter Web catalog for Iraq. Customers browse, select designs on their device, generate portrait selection images, then share/save those images and contact **@ge.to.ge** on Instagram. There are no customer accounts, checkout, payments, order records, or delivery forms.

## Requirements

- Flutter **3.47.4 stable** / Dart **3.13.3** or a compatible newer release.
- A Supabase project with PostgreSQL, Auth, and Storage when test mode is disabled.
- HTTPS hosting with an SPA fallback to `index.html`.
- Optional: Node for the share-bridge tests; Docker and Supabase CLI for local backend tests.

## First setup

```sh
flutter pub get
```

Test mode is enabled by default for now. Run `flutter run -d chrome` to browse 36 temporary designs across four categories, with bundled placeholder artwork and no Supabase connection. Search, sorting, pagination, details, selections, and image export work locally. Admin sign-in and editing are disabled in this mode. The inventory resets with the app; test selections persist separately from real catalog selections.

Control the mode with `USE_TEST_DATA` in your configuration JSON or `--dart-define=USE_TEST_DATA=true` / `--dart-define=USE_TEST_DATA=false`. Restart/rebuild after changing it; hot reload does not apply compile-time flags. Test mode takes precedence even when Supabase credentials are supplied.

To connect to real data, copy `config.example.json` to `config.local.json`, set `USE_TEST_DATA` to `false`, then provide your project URL and public anon/publishable key. Both values are public by design. **Never put a service-role/secret key, database password, or admin password in this file or any Flutter build.**

```json
{
  "USE_TEST_DATA": false,
  "SUPABASE_URL": "https://your-project.supabase.co",
  "SUPABASE_ANON_KEY": "your-public-publishable-key"
}
```

The legacy name `SUPABASE_ANON_KEY` accepts either an anon key or the newer publishable key. Configuration is compiled into Flutter Web; changing it requires a rebuild. Temporary inventory lives in `lib/repositories/test_catalog_repository.dart` and its placeholder images in `assets/test_catalog`. With test mode disabled and no Supabase configuration, the public catalog shows a retry state and `/admin` explains the missing setup.

## Database, RLS, and Storage

On a new project, run all files in `supabase/migrations` in filename order in the Supabase SQL editor. For an existing installation, apply `202609300001_tattoo_filters.sql` and then `202609300002_tattoo_images.sql` before using this version with Supabase. Alternatively link a project and apply migrations using the Supabase CLI:

```sh
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
```

The migration creates:

- `categories`, `products`, many-to-many `product_categories`, and an administrator allowlist `admin_users`.
- Each tattoo has one or both audiences (رجالي / نسائي), multiple body placements, and multiple categories. Main audience filters include shared designs under either audience. Multiple selected body placements match any selected place; audience, placement, category, and search filters combine together.
- The `catalog_products` view aggregates category memberships before pagination and applies caller RLS. Product saves use the transactional `save_catalog_product` RPC.
- Foreign keys, unique product codes, positive dimensions, nullable nonnegative prices, sort fields, timestamps, update triggers, area sorting, and indexes including trigram name/code search.
- Row-level security on every public application table.
- Public read access only for active products with at least one active category. A tattoo assigned to an active and a hidden category stays public, but its hidden category membership is omitted for public users. Direct product URLs and search follow the same rule. Explicit query filters apply even if an administrator is browsing the customer UI.
- Catalog management only for authenticated users listed in `admin_users`. Signing up or merely holding an authenticated token does not grant management access. Clients cannot read or modify the allowlist.
- Public buckets: `tattoo-images` (10 MiB), `tattoo-thumbnails` (2 MiB), and `category-images` (2 MiB), with PNG/JPEG/WebP allowlists. Only allowlisted administrators can upload, update, or delete objects.

Public bucket URLs remain readable to anyone who already knows the URL after a product is hidden. Deactivation removes catalog discoverability; it is not a revocation of previously shared images. For actual image removal, an administrator can delete the object in Supabase Storage. Do not remove a file still referenced by another record.

### Create the first administrator

1. In Supabase **Authentication → Users**, create an email/password user and confirm the email. No signup screen is exposed in this app.
2. Copy the user's UUID and run this only in the trusted SQL editor:

```sql
insert into public.admin_users (user_id)
values ('REPLACE-WITH-AUTH-USER-UUID');
```

3. Disable public user signups in Supabase Auth settings; email/password sign-in stays enabled. Local configuration already disables signup.
4. Visit `/admin`, then sign in. Never share this account with customers.
5. To revoke access, remove the user's row from `admin_users`; database/storage rules apply immediately. Revoke their Auth sessions as well when appropriate.

### Add your first category and tattoo

1. Open **التصنيفات** in the admin area and tap **+**.
2. Enter `وشومات سوار`, upload its image if available, set the numeric sort order, and save.
3. Open **المنتجات**, tap **+**, add one or more tattoo images, and enter a unique code such as `G2G-001`. Use **إضافة صورة** again for each additional image. The first image is the cover for cards and selection exports; use the star button to promote another image, or the delete button to remove an image from the gallery. At least one image is required. Customers can swipe, use arrows, or tap thumbnails to see every image and zoom into details.
4. Select رجالي, نسائي, or both; choose one or more body placements and one or more categories. Enter dimensions and price if wanted. Blank prices/dimensions are hidden publicly.
5. Set **ظاهر بالكتالوج**, **مميز**, and **وصل حديثاً** as needed.
6. Use **حفظ وإضافة وشم آخر** to keep the audiences, placements, categories, dimensions, and price but clear the code, name, and image for the next design.
7. To edit, tap a record. Use the sort-order number to reorder. Hide unavailable designs instead of deleting them. Deleting a category that contains products is prevented by its foreign key.

Uploads validate file extension, magic bytes, decoded dimensions, and size. Images above 24 megapixels are rejected before full decode. Original tattoo bytes are stored unmodified. A proportional 600-pixel PNG thumbnail preserves transparency. Category images use the optimized version. Failed/cancelled uploads attempt to remove newly staged objects. Replaced, previously saved images are intentionally retained; periodically review unreferenced objects in Storage before deleting them.

Extra images are stored in the ordered `additional_images` array, with `image_url` and optional `thumbnail_url` per image. Existing single-image tattoos need no changes. New uploads removed before saving or left in a cancelled editor are cleaned up; removing a previously saved image only removes its gallery reference and does not delete shared Storage objects.

## Run locally

```sh
flutter run -d chrome --dart-define-from-file=config.local.json
```

For a local Supabase backend:

```sh
npx supabase start -x realtime,imgproxy,edge-runtime,logflare,vector,supavisor,studio,mailpit,postgres-meta
npx supabase status
```

This project's local ports are API `15421`, PostgreSQL `15422`, and shadow DB `15420`, avoiding common Windows reserved ports. Copy the local API URL and **public** key into `config.local.json`. Local migrations run at first startup. Do not run `db reset` against a database containing important work. `supabase/seed.sql` is intentionally empty; test fixtures are kept out of production migrations.

## Web release and deployment

```sh
flutter analyze
flutter test
node tool/share_bridge_test.cjs
flutter build web --release --dart-define-from-file=config.production.json --dart-define=USE_TEST_DATA=false
```

Upload **only `build/web`** to static hosting. Do not deploy source files or private configuration. Deploy over HTTPS for native sharing. Flutter's initial runtime download is larger than an HTML-only site; the app keeps subsequent product requests paginated and uses thumbnails, lazy grid construction, browser image caching, and locally bundled Arabic typography.

Direct URLs must return the SPA entry point:

- Netlify/Cloudflare Pages: `web/_redirects` is copied to the build.
- Nginx: use `deployment/nginx.conf` and serve `build/web`.
- Vercel: `vercel.json` declares the output and route rewrite. Build Flutter locally or in a CI environment with Flutter installed, then deploy the prebuilt output.
- Any other host: existing assets must be served normally; unknown route paths fall back to `/index.html`.

Avoid caching `index.html`, `flutter_bootstrap.js`, and `main.dart.js` indefinitely. The supplied Nginx example forces revalidation. Browser installation is never required. The manifest is lightweight; no offline service-worker promise is made. Full offline catalog browsing is not guaranteed, but selected record snapshots persist and loaded data stays visible after pagination errors.

Local release preview, including deep links:

```sh
python tool/serve.py --port 8090 --directory build/web
```

## Sharing behavior and CORS

`SelectionRenderer` downloads each selected original image as bytes, decodes it with Flutter, and draws it proportionally using `BoxFit.contain` into a **1200 × 1680 PNG**. Six designs fit on each page; the last page expands for fewer designs, and one design receives a large single layout. Pages contain the brand, actual artwork, matching product codes/dimensions, page count, and Instagram handle. Full-resolution requests happen on details/export, not initial card loading.

Generation is sequential and disposes decoded images after drawing each one. If an image fails to load, generation fails visibly and the local selections remain. It never shares an incomplete grid while silently skipping an image. Availability and current product data are rechecked before generation; removed designs are reported and the customer can review before retrying.

`web/share.js` prepares image `File` objects before a user's share tap, checks `navigator.canShare({files})`, and invokes `navigator.share` synchronously from that tap. Cancellation leaves the preview open. Unsupported/rejected sharing exposes per-page save controls and Instagram instructions. Each page has its own save button because mobile browsers may block batches of downloads. A browser may open the image instead of downloading; the UI explains long-press saving. Object URLs remain alive while the preview is open and are revoked when it closes.

The Instagram button opens `https://ig.me/m/ge.to.ge`. It does **not** attach files to a DM. The customer chooses a native share destination or saves the images and attaches them manually in Instagram.

Supabase public Storage normally serves the CORS headers required for byte fetching. If using a custom CDN/proxy, it must also allow GET requests from your site origin and must not strip those headers. Test a real uploaded URL from the deployed site origin, then generate a selection. Do not work around CORS with an untrusted public proxy. All share image rendering uses fetched bytes, not tainted HTML image canvases.

## Architecture

- `lib/config.dart`: Supabase settings, brand, currency formatting, Instagram destination, pagination, export limits.
- `lib/models`: typed catalog records and queries.
- `lib/repositories`: public/admin catalog queries with bounded product pages and explicit public availability filtering.
- `lib/services/admin_service.dart`: authentication, authorization checks, mutations, validated uploads, thumbnails, cleanup.
- `lib/state`: debounced/race-safe pagination and serialized local selection persistence.
- `lib/services/selection_renderer.dart`: portable Dart/Flutter image composition.
- `lib/services/share`: conditional web adapter; replace the stub with a mobile sharing adapter for future Android/iOS delivery.
- `lib/services/analytics.dart`: no-op, non-PII event boundary for future analytics.
- `lib/ui/customer`, `lib/ui/admin`, `lib/ui/widgets`: screens and reusable presentation.
- `lib/app.dart`: clean, directly loadable routes.

No database queries are embedded in UI widgets. Bulk upload can call `save_catalog_product` with `category_ids`, `audiences`, and `body_placements`. The migration backfills existing category assignments and defaults existing tattoos to both audiences, with no assumed body placement; select placements when editing these records. Saved selections from the old single-category format still load. SQL uniqueness is the final protection against concurrent duplicate product codes.

To replace the wordmark, bundle your logo asset in `pubspec.yaml` and set `LOGO_ASSET` in the configuration JSON. Both the UI and export renderer read it. The Arabic font is bundled with its OFL license in `assets/fonts`.

## Verification

See `docs/VERIFICATION.md` for executed checks and remaining real-device/live deployment checks.

```sh
flutter analyze
flutter test
node tool/share_bridge_test.cjs
```

Against a disposable local Supabase backend, execute `supabase/tests/catalog_security.sql` as PostgreSQL administrator. It runs in a transaction and rolls back fixtures. It covers public filtering, anonymous writes, authenticated non-admin writes, privilege escalation, Storage policies, admin management, duplicate codes, and safe category deletion.

The tests' synthetic rectangular artwork is only a fixture for measuring export proportions; it is not G2G inventory. Add your own actual tattoo artwork through the admin area.

## Technical references

- [Supabase Flutter setup](https://supabase.com/docs/guides/getting-started/quickstarts/flutter)
- [Supabase range/select queries](https://supabase.com/docs/reference/dart/select)
- [Supabase Storage](https://supabase.com/docs/guides/storage/quickstart)
- [Dart JavaScript interop](https://dart.dev/interop/js-interop)
