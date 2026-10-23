# CameraHub v3.2 — Logical ERD

The physical schema (`001_full_schema.sql`) is authoritative. These diagrams emphasize the most important relationships; other lookup, media, audit, and event tables are present in the SQL.

## Marketplace and inspection
```mermaid
erDiagram
  users ||--o{ products : sells
  camera_models ||--o{ products : catalogues
  products ||--o{ conversations : discussed_in
  users ||--o{ conversations : buyer
  conversations ||--o{ chat_messages : contains
  conversations ||--o{ price_offers : negotiates
  products ||--o{ inspection_requests : inspected
  inspection_requests ||--o{ inspection_agreements : versions
  inspection_requests ||--o{ inspection_reports : generates
  inspection_reports ||--o{ inspection_results : checks
  inspection_reports ||--o{ inspection_findings : verifies_claims
  inspection_requests ||--o| inspection_fee_settlements : final_fee
  inspection_requests ||--o| inspection_reservations : optional_hold
```

## Orders, deposit, shipping and disputes
```mermaid
erDiagram
  products ||--o{ orders : ordered
  price_offers o|--o| orders : accepted_at_checkout
  orders ||--|| order_deposits : deposit
  orders ||--o{ payment_records : stages
  orders ||--o{ shipments : deliveries
  shipments ||--o{ shipment_events : logs
  orders ||--o| protection_windows : protects
  orders ||--o{ disputes : has
  orders ||--o{ cancellation_requests : cancellation
  orders ||--o{ refund_settlements : settles
  cancellation_requests o|--o{ refund_settlements : resolved_by
  disputes o|--o{ refund_settlements : resolved_by
  refund_settlements ||--o{ refund_transactions : executes
  orders ||--o{ payout_records : simulated_release
```

## Monetary semantics
- `orders.agreed_price_vnd`: mutually accepted listed/offer price.
- `orders.shipping_fee_vnd`: buyer-paid shipping quote locked at checkout or accepted before second payment.
- `orders.total_vnd`: generated `agreed_price_vnd + shipping_fee_vnd`.
- `orders.deposit_amount_vnd`: generated 10% of price, rounded to integer VND.
- `payment_records`: one successful simulated payment for DEPOSIT and one for BALANCE_AND_SHIPPING; retries may exist.
- `inspection_fee_records`: advance record; `inspection_fee_settlements`: final liability, not a cash transfer.
- `refund_settlements` and `refund_transactions`: decision vs. execution.
