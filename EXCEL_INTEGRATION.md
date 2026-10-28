# Excel desktop integration

Entry point: `importar-excel.html`, linked from the theoretical inventory upload.
The workbook is not published. Install the module from `excel/InventariosSupabase.bas`
into the original Windows Excel workbook. See `excel/INSTALACION.txt`.

## Data flow
The foreground SQL QueryTable refresh must succeed before sending. VBA reads the original
19 named columns and optional `Código de Barra` in DATA / FACTS62 (fallback table name INVENTARIOS), serializes
UTF-8 JSON and stages it via REST. No stored user passwords or service role keys.
An authenticated Inventarios writer generates a random one-use pass, valid for
30 minutes. Only its SHA-256 digest is stored. Only one unreceived pass is active
per user. The pass permits staging only, never reading or committing inventories.
A signed-in owner validates and explicitly commits the staged batch in the web UI.

The private upload table has RLS and no client table privileges. The receive RPC
is intentionally callable by anon, with the strong expiring capability and live
account check. Other RPCs require authentication, current app/write permissions
and ownership. Apply rechecks every warehouse using the existing ACL functions.
The advisor findings for SECURITY DEFINER and no direct private-table policies
are intentional for this API: bodies authorize access and table access is denied.

## Import semantics
- Bodega normalized to 3 digits; absent catalog codes are counted and skipped.
- Configured but unauthorized warehouses reject the batch.
- Cantidades is total units, preserved as numeric; no multiplication by Masterpack.
- Operative article code remains the existing integer key; raw textual codes and
  all original fields remain in the private staged payload. Duplicate normalized
  article + warehouse keys are rejected (including multiple societies).
- Masterpack accepts nonnegative integers or NULL when absent in the source. The preview reports missing Masterpack; total units do not depend on it.
- One source date; commit only on the current Honduras date.
- Only included warehouses are replaced. No unrelated warehouse is cleared.
- A transaction lock prevents two baseline imports from interleaving. A counts
  table lock prevents count insertion between freeze check and baseline commit.
- Current or previous counts in included warehouses block replacement. Closing a
  day is NOT implemented by this integration and must preserve those counts.
- Commit and import log are atomic; failure restores the old baseline. Applied
  batches return their result without reapplying if submitted again.
- 20k rows / 20MB JSON limit, 20 passes/hour/user. Only expired unapplied payloads
  older than 7 days are purged on a user's next pass request. Applied payloads stay.

Two existing baseline quantity columns were widened from integer to numeric:
`inventario_reporteria.inventario_reporteria` and
`inventarios_diarios.inventario_reporteria`. Physical count totals remain integers.
Quantity display helper now shows up to 8 decimal places; database values retain
numeric precision. Existing manual CSV importer remains a separate legacy flow;
this feature does not change its behavior or automatically run a daily closure.

## Validation
`npm ci && npm test` includes the existing regression suite, a local Postgres
(PGlite) transaction/security test, and a simulated DOM test of the new UI.
A production transaction tested pass creation, receiving, preview/omission and
single-use rejection, followed by ROLLBACK. No production inventory was imported.
VBA was reviewed statically, not executed: Windows Excel, SQL refresh, corporate
macro policy and outbound HTTPS require a real test on the user's BIA computer.
No original XLSM was rewritten, preserving its SQL connections and links.

Barcode extension: optional exact header `Código de Barra`, persisted to `codigo_barra` as text (NULL when absent/empty). Up to 100 characters, no control characters. VBA refuses numeric barcodes of 16+ digits; source lookup formulas must return text to preserve leading zeros. No existing inventories are backfilled or overwritten by this change.
