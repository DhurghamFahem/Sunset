-- Expand placement choices while preserving all previously saved keys.
-- arm and hand now display as ذراع كامل and الكف in the app.
alter table public.products
  drop constraint products_body_placements_check,
  add constraint products_body_placements_check check (
    body_placements <@ array[
      'arm', 'halfArm', 'wrist', 'hand', 'fingers', 'forearm',
      'shoulder', 'neck', 'collarbone', 'chest', 'abdomen', 'back',
      'fullBack', 'fullBackVertical', 'fullBackHorizontal', 'buttocks',
      'leg', 'ankle', 'foot', 'thigh'
    ]::text[]
    and array_position(body_placements, null) is null
  );
