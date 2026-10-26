# CameraHub Marketplace – PostgreSQL schema v3.2

## Files
- `001_full_schema.sql`: **fresh install only**, PostgreSQL 16+, `camerahub` schema, 43 tables, foreign keys, checks, partial unique indexes, indexes, and minimal seeds.
- `ERD.md`: component ERD (Mermaid) and relations.
- `002_remove_inspector_role.sql`: remove the retired inspection role without deleting accounts or historical reports. Application permissions are USER and ADMIN; legacy BUYER/SELLER storage codes remain compatible.

## Business rules adopted
- Buyer can purchase at listed price or accepted negotiated offer; buyer/seller conversation is linked to a single product.
- Optional inspection: `VOLUNTARY` or `DESCRIPTION_VERIFICATION`; snapshot original seller description. Requester pays unless agreed otherwise. For description verification the buyer initially advances the inspection cost; responsibility can be transferred to seller when material in-scope mismatch is verified. `INCONCLUSIVE` is reviewed, not automatically charged to seller.
- Inspection requested by buyer occurs **before** paying for the camera. Inspection hold is modeled but needs seller approval and configured expiry.
- New order has a 10% deposit (`1000` basis points), then 90% balance + buyer-paid shipping. Marketplace transaction fee is zero in this MVP.
- Shipment starts only after both simulated stages are paid. Mock shipping provider is seeded as `MOCK`.
- Protection is 48 hours after confirmed delivery AND buyer confirmation; disputes block simulated payout.
- Cancelling after deposit requires reason, decision, refund settlement; all monetary operations are **SIMULATED**.

## Install into an EMPTY database
```
createdb camerahub_dev
psql -v ON_ERROR_STOP=1 -d camerahub_dev -f 001_full_schema.sql
psql -v ON_ERROR_STOP=1 --single-transaction -d camerahub_dev -f 002_remove_inspector_role.sql
```
`pgcrypto` extension creation requires sufficient DB permissions. Make sure your PostgreSQL user has `CREATE` privileges; or have your database administrator enable the extension.

**Do not run on an existing CameraHub schema/database.** This file is not a migration or `DROP/CREATE` reset. If you have existing real data, back it up and prepare a versioned migration before proceeding.

Check:
```
psql -d camerahub_dev -c "SELECT count(*) FROM information_schema.tables WHERE table_schema='camerahub';"
psql -d camerahub_dev -c "SELECT tablename FROM pg_tables WHERE schemaname='camerahub' ORDER BY tablename;"
```
Expected table count: 43.

## Implementation-critical transactional invariants
**PostgreSQL constraints alone do not enforce all of these; implement them in domain services, protected by transactions/row locks, and test concurrency.**
1. Product cannot have multiple active orders. The unique partial index includes COMPLETED orders to prevent reselling one physical device from the same listing. Cancelled listings may be released only after reconciliation.
2. Match order seller to product owner; match buyer/seller to offer's conversation; accepted offer belongs to product, buyer, is not expired/consumed, and its price equals `orders.agreed_price_vnd`.
3. `orders.deposit_amount_vnd = round(agreed_price_vnd * 10%)`. The matching `order_deposits` row must be created in the same order transaction.
4. `payment_records` successful per `(order_id,payment_stage)` exactly once. Stage DEPOSIT amount = deposit; BALANCE_AND_SHIPPING amount = total minus deposit. Do not ship before both success states.
5. `inspection_requests.description_snapshot` is captured **server-side** from approved product information; results must relate to this snapshot, not mutable listing text.
6. `inspection_fee_settlements` buyer + seller final fees = total; refund/adjustment ledger must account for advances. A final fee settlement is not a payment transfer.
7. `inspection_reservations` active windows are managed by scheduler; `status=ACTIVE` index blocks duplicate active reservations, and expiry requires a transition.
8. Payout simulated release must not happen when a blocking dispute or cancellation exists. Payout/refund execution uses idempotency.
9. For cancellation refund, compute amount using total *successfully simulated* payments minus previously completed refunds. Never refund more than that total.
10. External shipping event deduplication uses provider event ID; validate provider signature/token and delivery milestones.
11. Private Object Storage keys must not be exposed directly; issue limited signed URLs after authorization.

## Not yet decided by the team
- Deadline for deposit and 90% payment; these are nullable timestamps (`deposit_deadline`, `balance_deadline`) and require explicit configured values in the app.
- Cancellation/forfeiture rate or cutoff per reason; `cancellation_policies.rules` intentionally stores policy versions without made-up rates.
- Exact inspection reservation duration; seller must approve each hold.
- Shipping quotes / policy when final delivery fee changes; enforce buyer confirmation in app before 2nd payment.

## Scope and validation
This schema is a *new design* (v3.2), not the earlier v2.1 DDL. It was structurally inspected (43 unique table definitions, FK references, statement wrapper), but **not executed against a live PostgreSQL instance** in this environment. Run the script on a development database and verify with integration tests before deployment. An actual 48-hour window and relevant policy are modeled, but actual funds are not held or settled by these tables.
