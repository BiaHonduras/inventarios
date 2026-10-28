# Daily close and immutable history

Use `cierre-dia.html`, linked as **Cierre e Histórico** in the inventory sidebar.
An active Inventarios user can read closures of their permitted sites. Only the
canonical Administrador, Jefatura ZN and Jefatura ZC roles may close a warehouse,
and the existing application/write/site ACL is rechecked in every RPC.
No account assignments or roles were changed by this feature.

## Workflow
Choose date, site and warehouse; validate; review the snapshot summary. A closure
requires a baseline and at least one physical count. Missing counted SKUs require
explicit acceptance. Undated justifications block closing because they cannot be
safely assigned to a day. Future Honduras dates cannot be closed. Historic dates
can be closed if their corresponding baseline/counts still exist.

The preview fingerprint includes all baseline, count and dated justification rows
and the undated justification count. If anything changes, confirmation fails and
the user must validate again. Confirmation snapshots first and then deletes only
that exact date and warehouse, in a single transaction. A failure rolls everything
back. The unique date/warehouse key and transaction advisory lock make duplicate
requests idempotent. Import and closure share the advisory lock. Table locks during
confirmation prevent a count/import edit from slipping between snapshot and cleanup.

## Stored history
`bia_acl_private.inventory_daily_closures` is a private immutable snapshot table:
id, fecha, bodega, sede, closed_at, closed_by, closed_name, resumen, datos.
`datos` includes full original rows under base, conteos, justificaciones and, when
available, fuente_excel (all original workbook fields from the latest applicable
confirmed upload). JSONB preserves decimal numbers, text barcodes and original row
IDs. Users never have direct SELECT/INSERT/UPDATE/DELETE on the snapshot table.
RLS is enabled with no direct policies intentionally: checked SECURITY DEFINER RPCs
are the only client access path, and their search_path is fixed. No closing RPC is
executable by anon. Advisor notices about authenticated definer RPCs and private
RLS tables without policies are intentional for this API, reviewed for these guards.

History is paginated 50 closures per page with date and warehouse filters. Detail
shows up to 200 original rows per dataset; Excel export includes all snapshot rows
on separate Resumen, Base, Conteos, Justificaciones and Fuente Excel sheets. IDs and
barcodes remain text as originally stored. This is historical storage in the same
database, not an independent disaster-recovery backup or a storage reduction.

Closed date/warehouse pairs reject subsequent inserts and updates in the three
working tables via private triggers. No automatic reopening or restoring function
is exposed. Other dates and warehouses remain open. Weekly expiration data and
article/warehouse catalogs are not cleared. Existing separate backup tables are
not repurposed or altered, avoiding their older integer column definitions.

The manual CSV importer now uses the same atomic staging/apply RPCs as Excel rather
than deleting the working baseline before an independent insert. Date/count locks,
warehouse permissions and closed-day write protection therefore also apply to CSV.
Current baseline fields and the Excel macro are unchanged by this feature.

## Verification
The automated local PostgreSQL (PGlite) test covers exact warehouse/date cleanup,
immutable snapshots, decimal/barcode/source preservation, canonical roles and sites,
missing-count acceptance, stale preview refusal, forced delete failure rollback,
idempotency, history access, direct privilege denial and closed-day insert guards.
DOM tests cover the preview/confirmation UI, mandatory acceptance and read-only
history. Existing inventory, session, scanner and Excel bridge tests remain in npm
test. A production read/preview was exercised inside a rolled-back transaction.
No real production day was closed and no production inventory records were removed.
