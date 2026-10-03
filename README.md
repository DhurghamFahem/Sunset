# G2G — Arabic herbal tattoo catalog

A mobile-first Flutter Web tattoo catalog and order manager for Iraq. Customers select designs and quantities, generate portrait images with a tracking code, and share/save images or contact **@ge.to.ge** on Instagram. Customer accounts and online payments are not required.

## Orders, delivery, and employees

Apply **all pending migrations**, including `202610030001_orders.sql` and `202610030002_staff_order_confirmation.sql`, before using real orders. The default test mode demonstrates the workflow in memory: orders, employees, and settings reset on reload. Production orders persist in Supabase. No production migration or deployment is performed by editing this repository.

- Preparing selection images creates a **Pending confirmation** order. Every page includes the same four-character uppercase letter/number code and each design's quantity. Quantities are 1–99 per design, with up to 100 distinct designs in an order. Failed export/network retries reuse the saved request token; a completed new export creates a new order.
- Codes are allocated transactionally with cryptographic randomness. A code cannot be reused within 30 days of its last allocation, or while an earlier order with that code remains pending, confirmed, packed, or shipped. Historical codes can repeat after that window; the permanent order UUID and creation date distinguish older orders.
- Open **طلباتي** (the receipt icon) to manage orders created on this device. Employees enter the required phone, governorate, and area/address and confirm the order in `/admin/orders`; customer name, social username, and source platform are optional. Customers do not see the completion form or initial confirmation button, including on the image-sharing screen. Customer tokens cannot edit these details or initially confirm an order. Available sources are Instagram, WhatsApp, TikTok, Facebook, Website, and Other.
- The lifecycle is **Pending confirmation → Confirmed → Packed → Shipped → Delivered / Partially accepted / Rejected**. Customers and staff can cancel pending, confirmed, or packed orders. After shipping, prices, quantities, customer details, and employee assignment are locked. Customers can acknowledge delivery, enter accepted quantities for a partial delivery, or reject the shipment. Staff can also record those outcomes. Completed/cancelled orders are closed.
- The four-character code is for identifying an order in conversation; it does **not** authorize reading or changing it. A random private capability is retained in the originating browser and never printed in images. Clearing browser data removes customer access on that device; staff can still find the order by code and date. Do not share browser storage containing these tokens.
- Open **`/admin/orders`** to search by code, phone, name, or username, filter by status, edit orders, assign an employee, and progress fulfillment. All private admin reads and mutations require an allowlisted administrator. Database functions enforce transitions, prices, accepted quantities, and optimistic versions; stale edits are rejected instead of silently overwriting another change. Audit events record actor, time, version, and state transitions, including edits that retain the current state.
- Original unit prices are snapshotted at creation. Staff may lower individual unit prices, set a discounted final total, or combine both. The final total cannot exceed the adjusted line subtotal plus delivery. The summary and booking message show original totals, item discounts, extra discount, total savings, delivery, and final amount. An originally unpriced tattoo must be priced by staff before confirmation; zero is an explicit valid price, not a placeholder for unknown prices.
- Confirmation attempts to copy an Arabic booking message containing the code, customer/address, every tattoo, quantities, original/discounted prices, delivery, and totals. A Copy button and selectable message remain available if the browser blocks automatic clipboard access. Sending the message remains a manual action.
- **`/admin/settings`** sets the default delivery fee for new orders (initially zero). Existing orders retain their delivery snapshot; staff may edit it before shipping.
- **`/admin/team`** manages employees using only name and phone and shows all-time order counts, fulfilled orders, accepted pieces, and accepted order value. Assignment is optional. Partial-delivery value charges delivery once when any pieces are accepted and allocates the additional discount proportionally across merchandise, rounded to the nearest dinar. No pieces accepted means zero accepted value. These are fulfillment metrics, not a payment ledger.

Order checks: `flutter test test/order_repository_test.dart test/order_ui_test.dart`; database authorization and lifecycle checks: execute `supabase/tests/orders.sql` against a local database with all migrations applied. SQL fixtures are rolled back.

## Requirements

- Flutter **3.47.4 stable** / Dart **3.13.3** or a compatible newer release.
- A Supabase project with PostgreSQL, Auth, and Storage when test mode is disabled.
- HTTPS hosting with an SPA fallback to `index.html`.
- Optional: Node for the share-bridge tests; Docker and Supabase CLI for local backend tests.

## First setup

```sh
flutter pub get
```

Test mode is enabled by default for now. Run `flutter run -d chrome` to browse 36 named temporary designs across four categories and six exact sizes, with search tags, bundled placeholder galleries, and no Supabase connection. Search, sorting, pagination, details, selections, and image export work locally. Open `/admin` and sign in with **test@gmail.com** / **1234** to test admin management, including category/product edits and image uploads. This demo account works only with `USE_TEST_DATA=true`; all changes and the login session stay local and reset when the app reloads. The inventory resets with the app; test selections persist separately from real catalog selections.

Control the mode with `USE_TEST_DATA` in your configuration JSON or `--dart-define=USE_TEST_DATA=true` / `--dart-define=USE_TEST_DATA=false`. Restart/rebuild after changing it; hot reload does not apply compile-time flags. Test mode takes precedence even when Supabase credentials are supplied.

To connect to real data, copy `config.example.json` to `config.local.json`, set `USE_TEST_DATA` to `false`, then provide your project URL and public anon/publishable key. Both values are public by design. **Never put a service-role/secret key, database password, or real admin password in this file or any Flutter build.**

```json
{
  "USE_TEST_DATA": false,
  "SUPABASE_URL": "https://your-project.supabase.co",
  "SUPABASE_ANON_KEY": "your-public-publishable-key"
}
```

The legacy name `SUPABASE_ANON_KEY` accepts either an anon key or the newer publishable key. Configuration is compiled into Flutter Web; changing it requires a rebuild. Temporary inventory lives in `lib/repositories/test_catalog_repository.dart` and its placeholder images in `assets/test_catalog`. With test mode disabled and no Supabase configuration, the public catalog shows a retry state and `/admin` explains the missing setup.

## Database, RLS, and Storage

On a new project, run all files in `supabase/migrations` in filename order in the Supabase SQL editor. For an existing installation, apply any pending migrations in order, including `202610010001_names_sizes_tags.sql`, before using this version with Supabase. Alternatively link a project and apply migrations using the Supabase CLI:

```sh
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push
```

The migration creates:

- `categories`, `products`, many-to-many `product_categories`, and an administrator allowlist `admin_users`.
- Each tattoo has one or both audiences (رجالي / نسائي), multiple body placements, and multiple categories. Main audience filters include shared designs under either audience. Multiple selected body placements match any selected place; audience, placement, category, and search filters combine together.
- The `catalog_products` view aggregates category memberships before pagination and applies caller RLS. Product saves use the transactional `save_catalog_product` RPC.
- Customer cards, details, selections, accessibility labels, and exported images display the tattoo name. Codes remain in admin screens and admin search. This is a presentation distinction; codes are not secrets and are still present in catalog records.
- Exact size chips use distinct width × height pairs from publicly available inventory (`catalog_available_sizes`). Selecting several sizes matches any complete pair, preserving orientation; 5 × 8 and 8 × 5 are different sizes. The existing size sort still orders by area.
- Customer search matches every word across the name and tags, allowing partial matches. It ignores English case, Arabic diacritics/tatweel, and common Arabic letter variants. Add synonyms or English tags to make those terms searchable. Admin search additionally includes the code. Normalized search columns have trigram indexes.
- The visible **الوسوم** filter offers distinct tags from publicly available tattoos. Customers can select multiple tags to match any selected tag, combined with audience, placement, exact size, category, and text search. **كل الوسوم** clears only tag selections. Apply `202610010002_tag_filters.sql` for the tag-options RPC and array index when using Supabase.
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
4. Enter the required customer-facing tattoo name and exact width and height in centimeters. Select رجالي, نسائي, or both; choose one or more body placements and one or more categories. Add search tags separated by Arabic/English commas, semicolons, or newlines (up to 30 tags, 64 characters each); normalized duplicates are removed. Price remains optional.
5. Set **ظاهر بالكتالوج**, **مميز**, and **وصل حديثاً** as needed.
6. Use **حفظ وإضافة وشم آخر** to keep the audiences, placements, categories, dimensions, and price but clear the code, name, tags, and images for the next design.
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

### GitHub Pages: deploy with a `[d]` commit

The workflow in `.github/workflows/deploy-pages.yml` builds and deploys when the **latest commit in a push to the repository's default branch** starts with `[d]`, for example `[d] update catalog`. Other pushes show a skipped workflow. When pushing several commits together, only the latest commit's message controls deployment. For squash merges, put the prefix in the final squash commit message.

1. Push this repository, including the workflow, to GitHub.
2. In **Settings → Pages → Build and deployment**, set **Source** to **GitHub Actions**.
3. By default, deployments use the bundled test catalog. For real Supabase data, add repository variables under **Settings → Secrets and variables → Actions → Variables**: `USE_TEST_DATA` = `false`, `SUPABASE_URL`, and `SUPABASE_ANON_KEY` (the public anon/publishable key). These values are compiled into the public website; never use a service-role key. Local configuration files are not used by this workflow.
4. Commit and push to the default branch:

   ```sh
   git commit -m "[d] deploy site"
   git push
   ```

   To deploy without changing files, use `git commit --allow-empty -m "[d] deploy site"`, then push.

The workflow uses Flutter 3.47.4, detects the Pages base path (including repository subdirectories and custom domains), and uploads only `build/web`. The deployment URL appears in the Actions run's `github-pages` environment. It also copies `index.html` to `404.html` so direct links such as `/admin` load the Flutter router. GitHub Pages still returns HTTP 404 for these deep-link requests; navigation within the app works normally.

See [GitHub's custom Pages workflow documentation](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages) for repository setup and deployment permissions.

#### Custom domain: getoge.com

In **Settings → Pages → Custom domain**, enter `getoge.com` and save before updating DNS. At your DNS provider, set these records:

| Type | Name | Value |
| --- | --- | --- |
| A | @ | 185.199.108.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |
| CNAME | www | YOUR_USERNAME.github.io |

Replace `YOUR_USERNAME` with the GitHub repository owner's username. Once GitHub validates DNS and provisions the certificate, enable **Enforce HTTPS**. Push a new `[d]` commit after saving the custom domain so the workflow rebuilds for the domain's root path.

This Actions deployment reads the domain from GitHub Pages settings; no repository `CNAME` file is required. See [GitHub's custom domain instructions](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site).

## Sharing behavior and CORS

`SelectionRenderer` downloads each selected cover image as bytes, decodes it with Flutter, and draws it proportionally using `BoxFit.contain` into a **1200 × 1680 PNG**. Six designs fit on each page; the last page expands for fewer designs, and one design receives a large single layout. Pages contain the brand, actual artwork, tattoo names/dimensions, page count, and Instagram handle. Full-resolution requests happen on details/export, not initial card loading.

Generation is sequential and disposes decoded images after drawing each one. If an image fails to load, generation fails visibly and the local selections remain. It never shares an incomplete grid while silently skipping an image. Availability and current product data are rechecked before generation; removed designs are reported and the customer can review before retrying.

The customer flow always saves the generated selection images, then opens the Instagram chat. It does not show the device's app/recipient sharing picker. Each generated page is saved separately because mobile browsers may block batches of downloads; after each save attempt, the preview advances to the next unsaved page. Once every page has been requested, the main button opens the chat, with a reminder to confirm the images were saved and attach them manually. Customers can save an image again. A browser may open the image instead of downloading; the UI explains long-press saving. `web/share.js` prepares downloadable image files; their object URLs remain alive while the preview is open and are revoked when it closes.

The Instagram button opens `https://ig.me/m/ge.to.ge`. It does **not** attach files to a DM. The customer attaches the saved selection images manually in that chat.

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

No database queries are embedded in UI widgets. Bulk upload calls `save_catalog_product` with the required `name_ar`, `code`, `width_cm`, `height_cm`, `category_ids`, `audiences`, and `body_placements`, plus optional `tags` and gallery fields. Migrations backfill existing category assignments and default existing tattoos to both audiences, with no assumed body placement. Previously unnamed tattoos receive the neutral name `وشم عشبي`; replace it when editing. Existing missing dimensions are not invented and do not appear as size options until completed. Saved selections from older formats still load. SQL uniqueness is the final protection against concurrent duplicate product codes.

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
