-- CameraHub Marketplace MVP v3.2 - PostgreSQL 16+
-- Every amount is an integer number of VND. Payments, fees, payouts and refunds are simulated.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE SCHEMA IF NOT EXISTS camerahub;
SET search_path TO camerahub, public;

CREATE TABLE users (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), email text NOT NULL, password_hash text NOT NULL,
 full_name varchar(160) NOT NULL, phone varchar(20), account_status varchar(20) NOT NULL DEFAULT 'ACTIVE'
 CHECK (account_status IN ('ACTIVE','SUSPENDED','CLOSED')),
 email_verified_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_users_email_lower ON users (lower(email));
CREATE TABLE roles (code varchar(20) PRIMARY KEY CHECK (code IN ('BUYER','SELLER','INSPECTOR','ADMIN')));
INSERT INTO roles(code) VALUES ('BUYER'),('SELLER'),('INSPECTOR'),('ADMIN');
CREATE TABLE user_roles (
 user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 role_code varchar(20) NOT NULL REFERENCES roles(code), PRIMARY KEY(user_id,role_code)
);
CREATE TABLE seller_verifications (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), seller_id uuid NOT NULL REFERENCES users(id),
 status varchar(24) NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','VERIFIED','REJECTED','NEEDS_REVISION')),
 evidence_private_key text, review_note text, reviewed_by uuid REFERENCES users(id), reviewed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_active_seller_verification ON seller_verifications(seller_id)
 WHERE status IN ('PENDING','VERIFIED','NEEDS_REVISION');
CREATE TABLE user_addresses (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id),
 recipient_name varchar(160) NOT NULL, phone varchar(20) NOT NULL, province text NOT NULL, district text,
 ward text, street_address text NOT NULL, is_default boolean NOT NULL DEFAULT false, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_default_address ON user_addresses(user_id) WHERE is_default;
CREATE TABLE brands (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), name varchar(100) NOT NULL UNIQUE);
CREATE TABLE camera_models (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), brand_id uuid NOT NULL REFERENCES brands(id),
 model_name varchar(160) NOT NULL, device_type varchar(20) NOT NULL CHECK(device_type IN ('BODY','LENS','OTHER')),
 specs jsonb NOT NULL DEFAULT '{}'::jsonb, UNIQUE(brand_id,model_name,device_type)
);
CREATE TABLE products (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), seller_id uuid NOT NULL REFERENCES users(id), model_id uuid NOT NULL REFERENCES camera_models(id),
 title varchar(240) NOT NULL, serial_number_private text, serial_last4 varchar(4), shutter_count integer CHECK(shutter_count>=0),
 price_vnd bigint NOT NULL CHECK(price_vnd>0), description text NOT NULL, condition_notes text NOT NULL,
 repair_history text, accessories text, listing_status varchar(24) NOT NULL DEFAULT 'DRAFT'
 CHECK(listing_status IN ('DRAFT','PENDING_REVIEW','NEEDS_REVISION','REJECTED','PUBLISHED','RESERVED','SOLD','HIDDEN')),
 inspection_badge varchar(20) NOT NULL DEFAULT 'NOT_INSPECTED'
 CHECK(inspection_badge IN ('NOT_INSPECTED','CERTIFIED','NOT_CERTIFIED','EXPIRED')),
 version integer NOT NULL DEFAULT 0 CHECK(version>=0), reviewed_by uuid REFERENCES users(id), reviewed_at timestamptz,
 rejection_reason text, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_products_search ON products(listing_status,model_id,price_vnd,created_at DESC);
CREATE INDEX idx_products_seller ON products(seller_id,created_at DESC);
CREATE TABLE product_media (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), product_id uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
 storage_key text NOT NULL, media_type varchar(12) NOT NULL CHECK(media_type IN ('IMAGE','VIDEO')),
 sort_order integer NOT NULL DEFAULT 0, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_product_media ON product_media(product_id,sort_order);
CREATE TABLE product_status_history (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), product_id uuid NOT NULL REFERENCES products(id),
 old_status text, new_status text NOT NULL, actor_id uuid REFERENCES users(id), reason text,
 occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE inspection_check_definitions (
 code varchar(50) PRIMARY KEY, display_name varchar(150) NOT NULL, device_type varchar(20),
 required_for_certification boolean NOT NULL DEFAULT true, active boolean NOT NULL DEFAULT true
);
INSERT INTO inspection_check_definitions(code,display_name,device_type) VALUES
 ('SERIAL_MATCH','Đối chiếu model và serial',NULL),('SENSOR','Sensor','BODY'),
 ('SHUTTER','Shutter','BODY'),('AUTOFOCUS','Autofocus',NULL),('LCD_EVF','Màn hình / EVF','BODY'),
 ('BUTTONS','Nút bấm',NULL),('PORTS','Cổng kết nối','BODY'),('EXTERIOR','Ngoại hình',NULL);
CREATE TABLE inspection_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), product_id uuid NOT NULL REFERENCES products(id),
 seller_id uuid NOT NULL REFERENCES users(id), buyer_id uuid REFERENCES users(id), inspector_id uuid REFERENCES users(id),
 initiated_by uuid NOT NULL REFERENCES users(id), quoted_fee_vnd bigint NOT NULL CHECK(quoted_fee_vnd>=0),
 status varchar(30) NOT NULL DEFAULT 'REQUESTED' CHECK(status IN
 ('REQUESTED','NEGOTIATING','AGREED','ASSIGNED','DEVICE_RECEIVED','IN_PROGRESS','REPORT_PENDING','COMPLETED','CANCELLED')),
 scheduled_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK (buyer_id IS NULL OR buyer_id <> seller_id)
);
CREATE UNIQUE INDEX uq_open_inspection_per_product ON inspection_requests(product_id)
 WHERE status NOT IN ('COMPLETED','CANCELLED');
CREATE TABLE inspection_agreements (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), request_id uuid NOT NULL REFERENCES inspection_requests(id),
 version integer NOT NULL CHECK(version>0), proposed_by uuid NOT NULL REFERENCES users(id),
 buyer_share_pct integer NOT NULL CHECK(buyer_share_pct BETWEEN 0 AND 100),
 seller_share_pct integer NOT NULL CHECK(seller_share_pct BETWEEN 0 AND 100),
 fee_total_vnd bigint NOT NULL CHECK(fee_total_vnd>=0),
 buyer_fee_vnd bigint NOT NULL CHECK(buyer_fee_vnd>=0), seller_fee_vnd bigint NOT NULL CHECK(seller_fee_vnd>=0),
 status varchar(16) NOT NULL DEFAULT 'PROPOSED' CHECK(status IN ('PROPOSED','ACCEPTED','REJECTED','SUPERSEDED','CANCELLED')),
 accepted_by uuid REFERENCES users(id), accepted_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(request_id,version), CHECK(buyer_share_pct+seller_share_pct=100),
 CHECK(buyer_fee_vnd+seller_fee_vnd=fee_total_vnd)
);
CREATE UNIQUE INDEX uq_accepted_agreement ON inspection_agreements(request_id) WHERE status='ACCEPTED';
CREATE UNIQUE INDEX uq_proposed_agreement ON inspection_agreements(request_id) WHERE status='PROPOSED';
CREATE TABLE inspection_fee_records (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), agreement_id uuid NOT NULL REFERENCES inspection_agreements(id),
 payer_id uuid NOT NULL REFERENCES users(id), amount_vnd bigint NOT NULL CHECK(amount_vnd>=0),
 status varchar(24) NOT NULL DEFAULT 'SIMULATED_PENDING'
 CHECK(status IN ('SIMULATED_PENDING','SIMULATED_PAID','SIMULATED_REFUNDED','WAIVED')),
 recorded_at timestamptz NOT NULL DEFAULT now(), UNIQUE(agreement_id,payer_id)
);
CREATE TABLE inspection_reports (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), request_id uuid NOT NULL REFERENCES inspection_requests(id),
 inspector_id uuid NOT NULL REFERENCES users(id), report_version integer NOT NULL CHECK(report_version>0),
 device_serial_snapshot text, certification_status varchar(20) NOT NULL
 CHECK(certification_status IN ('CERTIFIED','NOT_CERTIFIED','EXPIRED')),
 limitations text, summary text NOT NULL, inspected_at timestamptz NOT NULL, issued_at timestamptz NOT NULL DEFAULT now(),
 superseded_at timestamptz, UNIQUE(request_id,report_version)
);
CREATE TABLE inspection_results (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), report_id uuid NOT NULL REFERENCES inspection_reports(id),
 check_code varchar(50) NOT NULL REFERENCES inspection_check_definitions(code),
 result varchar(12) NOT NULL CHECK(result IN ('PASS','FAIL','WARNING','NOT_TESTED')),
 notes text, evidence_storage_key text, UNIQUE(report_id,check_code)
);
CREATE INDEX idx_inspection_reports_request ON inspection_reports(request_id,issued_at DESC);

CREATE TABLE orders (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), product_id uuid NOT NULL REFERENCES products(id),
 buyer_id uuid NOT NULL REFERENCES users(id), seller_id uuid NOT NULL REFERENCES users(id),
 agreed_price_vnd bigint NOT NULL CHECK(agreed_price_vnd>0), shipping_fee_vnd bigint NOT NULL DEFAULT 0 CHECK(shipping_fee_vnd>=0),
 transaction_fee_vnd bigint NOT NULL DEFAULT 0 CHECK(transaction_fee_vnd=0),
 total_vnd bigint GENERATED ALWAYS AS (agreed_price_vnd + shipping_fee_vnd) STORED,
 product_snapshot jsonb NOT NULL, shipping_address_snapshot jsonb NOT NULL,
 order_status varchar(26) NOT NULL DEFAULT 'AWAITING_DEPOSIT' CHECK(order_status IN
 ('AWAITING_DEPOSIT','AWAITING_BALANCE','READY_TO_SHIP','SHIPPING','DELIVERED','PROTECTION_ACTIVE','DISPUTED','CANCELLATION_REVIEW','REFUND_PROCESSING','COMPLETED','CANCELLED','DELIVERY_EXCEPTION')),
 payment_deadline timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 CHECK(buyer_id<>seller_id)
);
-- Only one live order per physical product, including the dispute/refund workflow.
CREATE UNIQUE INDEX uq_live_order_per_product ON orders(product_id) WHERE order_status NOT IN ('CANCELLED');
CREATE INDEX idx_orders_buyer ON orders(buyer_id,created_at DESC);
CREATE INDEX idx_orders_seller ON orders(seller_id,created_at DESC);
CREATE TABLE payment_records (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), order_id uuid NOT NULL REFERENCES orders(id),
 amount_vnd bigint NOT NULL CHECK(amount_vnd>=0), payment_mode varchar(20) NOT NULL DEFAULT 'SIMULATION' CHECK(payment_mode='SIMULATION'),
 status varchar(28) NOT NULL DEFAULT 'SIMULATED_PENDING' CHECK(status IN
 ('SIMULATED_PENDING','SIMULATED_PAID','SIMULATED_FAILED','SIMULATED_CANCELLED')),
 idempotency_key text NOT NULL UNIQUE, simulated_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
-- One successful simulation allowed PER payment stage; see payment_stage index added below.
CREATE TABLE shipping_providers (
 code varchar(50) PRIMARY KEY, display_name varchar(120) NOT NULL, adapter_type varchar(15) NOT NULL DEFAULT 'MOCK'
 CHECK(adapter_type IN ('MOCK','REAL')), active boolean NOT NULL DEFAULT true
);
INSERT INTO shipping_providers(code,display_name) VALUES('MOCK','CameraHub Mock Shipping');
CREATE TABLE shipping_quotes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), order_id uuid REFERENCES orders(id), provider_code varchar(50) NOT NULL REFERENCES shipping_providers(code),
 amount_vnd bigint NOT NULL CHECK(amount_vnd>=0), quote_reference text, expires_at timestamptz NOT NULL,
 quote_data jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE shipments (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), order_id uuid NOT NULL REFERENCES orders(id),
 provider_code varchar(50) NOT NULL REFERENCES shipping_providers(code), external_order_id text,
 tracking_number text, status varchar(26) NOT NULL DEFAULT 'CREATED' CHECK(status IN
 ('CREATED','PICKUP_REQUESTED','PICKED_UP','IN_TRANSIT','DELIVERED','DELIVERY_FAILED','CANCELLED','LOST')),
 is_current boolean NOT NULL DEFAULT true, delivered_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_current_shipment ON shipments(order_id) WHERE is_current;
CREATE UNIQUE INDEX uq_external_shipment ON shipments(provider_code,external_order_id) WHERE external_order_id IS NOT NULL;
CREATE TABLE shipment_events (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), shipment_id uuid NOT NULL REFERENCES shipments(id),
 provider_event_id text, event_type varchar(50) NOT NULL, event_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
 occurred_at timestamptz NOT NULL, received_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_shipment_event ON shipment_events(shipment_id,provider_event_id) WHERE provider_event_id IS NOT NULL;
CREATE TABLE protection_windows (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), order_id uuid NOT NULL UNIQUE REFERENCES orders(id),
 delivered_at timestamptz NOT NULL, buyer_received_at timestamptz NOT NULL, starts_at timestamptz NOT NULL,
 ends_at timestamptz NOT NULL, status varchar(16) NOT NULL DEFAULT 'ACTIVE' CHECK(status IN
 ('ACTIVE','ON_HOLD','RELEASED','REFUNDED')),
 CHECK(starts_at>=delivered_at AND starts_at>=buyer_received_at AND ends_at=starts_at+interval '48 hours')
);
CREATE TABLE disputes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), order_id uuid NOT NULL REFERENCES orders(id),
 opened_by uuid NOT NULL REFERENCES users(id), reason_code varchar(50) NOT NULL, description text NOT NULL,
 status varchar(25) NOT NULL DEFAULT 'OPEN' CHECK(status IN
 ('OPEN','WAITING_SELLER','INVESTIGATING','DECIDED','RESOLVING','CLOSED','REJECTED')),
 blocks_release boolean NOT NULL DEFAULT false, created_at timestamptz NOT NULL DEFAULT now(), closed_at timestamptz
);
CREATE INDEX idx_disputes_order_status ON disputes(order_id,status);
CREATE UNIQUE INDEX uq_active_dispute_per_order ON disputes(order_id) WHERE status NOT IN ('CLOSED','REJECTED');
CREATE TABLE dispute_evidence (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), dispute_id uuid NOT NULL REFERENCES disputes(id),
 uploaded_by uuid NOT NULL REFERENCES users(id), evidence_storage_key text NOT NULL,
 evidence_type varchar(20) NOT NULL CHECK(evidence_type IN ('IMAGE','VIDEO','DOCUMENT')),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE dispute_decisions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), dispute_id uuid NOT NULL REFERENCES disputes(id),
 decided_by uuid NOT NULL REFERENCES users(id), decision_type varchar(20) NOT NULL CHECK(decision_type IN
 ('RELEASE','FULL_REFUND','PARTIAL_REFUND','MORE_EVIDENCE')),
 refund_amount_vnd bigint CHECK(refund_amount_vnd>=0), reason text NOT NULL, decided_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE payout_records (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), order_id uuid NOT NULL REFERENCES orders(id),
 amount_vnd bigint NOT NULL CHECK(amount_vnd>=0), payout_mode varchar(20) NOT NULL DEFAULT 'SIMULATION' CHECK(payout_mode='SIMULATION'),
 status varchar(24) NOT NULL DEFAULT 'SIMULATED_PENDING' CHECK(status IN
 ('SIMULATED_PENDING','SIMULATED_RELEASED','SIMULATED_FAILED')),
 idempotency_key text NOT NULL UNIQUE, completed_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_released_payout ON payout_records(order_id) WHERE status='SIMULATED_RELEASED';
CREATE TABLE refund_records (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), order_id uuid NOT NULL REFERENCES orders(id),
 dispute_id uuid REFERENCES disputes(id), amount_vnd bigint NOT NULL CHECK(amount_vnd>=0),
 refund_mode varchar(20) NOT NULL DEFAULT 'SIMULATION' CHECK(refund_mode='SIMULATION'),
 status varchar(28) NOT NULL DEFAULT 'SIMULATED_PENDING' CHECK(status IN
 ('SIMULATED_PENDING','SIMULATED_REFUNDED','SIMULATED_FAILED')),
 idempotency_key text NOT NULL UNIQUE, completed_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE ai_chat_sessions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid REFERENCES users(id),
 anonymous_session_token_hash text, created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(user_id IS NOT NULL OR anonymous_session_token_hash IS NOT NULL)
);
CREATE TABLE ai_chat_messages (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), session_id uuid NOT NULL REFERENCES ai_chat_sessions(id) ON DELETE CASCADE,
 sender_role varchar(12) NOT NULL CHECK(sender_role IN ('USER','ASSISTANT','SYSTEM')),
 content text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE notifications (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), user_id uuid NOT NULL REFERENCES users(id),
 type varchar(80) NOT NULL, payload jsonb NOT NULL DEFAULT '{}'::jsonb,
 read_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_unread ON notifications(user_id,created_at DESC) WHERE read_at IS NULL;
CREATE TABLE audit_logs (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), actor_id uuid REFERENCES users(id),
 entity_type varchar(80) NOT NULL, entity_id uuid NOT NULL, action varchar(80) NOT NULL,
 old_data jsonb, new_data jsonb, correlation_id text, occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_entity ON audit_logs(entity_type,entity_id,occurred_at DESC);
CREATE INDEX idx_audit_actor ON audit_logs(actor_id,occurred_at DESC);

-- CameraHub v3.2 new modules. This is a FRESH INSTALL schema; do not run on an existing v2.1 DB.
-- Buyer and seller negotiation
CREATE TABLE conversations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), product_id uuid NOT NULL REFERENCES products(id),
 buyer_id uuid NOT NULL REFERENCES users(id), seller_id uuid NOT NULL REFERENCES users(id),
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(product_id,buyer_id,seller_id), CHECK (buyer_id<>seller_id)
);
CREATE TABLE chat_messages (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), conversation_id uuid NOT NULL REFERENCES conversations(id),
 sender_id uuid NOT NULL REFERENCES users(id), message_type varchar(16) NOT NULL DEFAULT 'TEXT'
 CHECK(message_type IN ('TEXT','SYSTEM','OFFER_NOTICE')), content text NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_chat_messages_page ON chat_messages(conversation_id,created_at DESC,id DESC);
CREATE TABLE price_offers (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), conversation_id uuid NOT NULL REFERENCES conversations(id),
 product_id uuid NOT NULL REFERENCES products(id), proposed_by uuid NOT NULL REFERENCES users(id),
 recipient_id uuid NOT NULL REFERENCES users(id), previous_offer_id uuid REFERENCES price_offers(id),
 offered_price_vnd bigint NOT NULL CHECK(offered_price_vnd>0),
 status varchar(16) NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','ACCEPTED','REJECTED','COUNTERED','EXPIRED','WITHDRAWN','CONSUMED')),
 expires_at timestamptz NOT NULL, accepted_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(proposed_by<>recipient_id), CHECK(expires_at>created_at)
);
CREATE INDEX idx_offers_conversation ON price_offers(conversation_id,created_at DESC);
CREATE UNIQUE INDEX uq_pending_offer_in_conversation ON price_offers(conversation_id) WHERE status='PENDING';
-- New optional structured reference; one offer can fund at most one order, including cancelled ones.
ALTER TABLE orders ADD COLUMN accepted_offer_id uuid UNIQUE REFERENCES price_offers(id);

-- Description verification / voluntary inspection metadata
ALTER TABLE inspection_requests ADD COLUMN request_type varchar(32) NOT NULL DEFAULT 'VOLUNTARY'
 CHECK(request_type IN ('VOLUNTARY','DESCRIPTION_VERIFICATION'));
ALTER TABLE inspection_requests ADD COLUMN description_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE inspection_requests ADD COLUMN claims_to_verify jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE inspection_requests ADD CONSTRAINT chk_verification_needs_buyer CHECK(request_type<>'DESCRIPTION_VERIFICATION' OR buyer_id IS NOT NULL);
-- Initial payer is explicit even when final responsibility differs after verification.
ALTER TABLE inspection_fee_records ADD COLUMN fee_stage varchar(20) NOT NULL DEFAULT 'ADVANCE'
 CHECK(fee_stage IN ('ADVANCE','ADJUSTMENT','REFUND'));
CREATE TABLE inspection_findings (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), report_id uuid NOT NULL REFERENCES inspection_reports(id),
 inspected_field varchar(80) NOT NULL, advertised_value text, observed_value text,
 conclusion varchar(16) NOT NULL CHECK(conclusion IN ('MATCH','MISMATCH','INCONCLUSIVE','NOT_TESTED')),
 details text, UNIQUE(report_id,inspected_field)
);
CREATE TABLE inspection_fee_settlements (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), request_id uuid NOT NULL UNIQUE REFERENCES inspection_requests(id),
 buyer_final_fee_vnd bigint NOT NULL CHECK(buyer_final_fee_vnd>=0),
 seller_final_fee_vnd bigint NOT NULL CHECK(seller_final_fee_vnd>=0),
 fee_total_vnd bigint NOT NULL CHECK(fee_total_vnd>=0),
 outcome varchar(24) NOT NULL CHECK(outcome IN ('MATCH','MISMATCH','INCONCLUSIVE','VOLUNTARY','CANCELLED')),
 decision_reason text NOT NULL, decided_by uuid REFERENCES users(id), created_at timestamptz NOT NULL DEFAULT now(),
 CHECK(buyer_final_fee_vnd+seller_final_fee_vnd=fee_total_vnd)
);
CREATE TABLE inspection_reservations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), request_id uuid NOT NULL UNIQUE REFERENCES inspection_requests(id),
 product_id uuid NOT NULL REFERENCES products(id), buyer_id uuid NOT NULL REFERENCES users(id),
 approved_by_seller uuid NOT NULL REFERENCES users(id), status varchar(20) NOT NULL DEFAULT 'ACTIVE'
 CHECK(status IN ('ACTIVE','EXPIRED','CANCELLED','CONVERTED')),
 expires_at timestamptz NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_active_inspection_reservation ON inspection_reservations(product_id) WHERE status='ACTIVE';
CREATE INDEX idx_expiring_inspection_reservations ON inspection_reservations(expires_at) WHERE status='ACTIVE';

-- The full price is locked on order creation; buyer pays 10% deposit then 90% + shipping.
ALTER TABLE orders ADD COLUMN inspection_request_id uuid REFERENCES inspection_requests(id);
ALTER TABLE orders ADD COLUMN deposit_rate_bps integer NOT NULL DEFAULT 1000 CHECK(deposit_rate_bps=1000);
ALTER TABLE orders ADD COLUMN deposit_amount_vnd bigint GENERATED ALWAYS AS ((agreed_price_vnd * deposit_rate_bps + 5000) / 10000) STORED;
ALTER TABLE orders ADD COLUMN balance_product_amount_vnd bigint GENERATED ALWAYS AS (agreed_price_vnd - ((agreed_price_vnd * deposit_rate_bps + 5000) / 10000)) STORED;
ALTER TABLE orders ADD COLUMN deposit_deadline timestamptz;
ALTER TABLE orders ADD COLUMN balance_deadline timestamptz;
CREATE TABLE order_deposits (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), order_id uuid NOT NULL UNIQUE REFERENCES orders(id),
 deposit_rate_bps integer NOT NULL DEFAULT 1000 CHECK(deposit_rate_bps=1000),
 amount_vnd bigint NOT NULL CHECK(amount_vnd>0),
 status varchar(22) NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','PAID','APPLIED','REFUND_PENDING','REFUNDED','FORFEITED','CANCELLED')),
 paid_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE payment_records ADD COLUMN payment_stage varchar(24) NOT NULL DEFAULT 'DEPOSIT'
 CHECK(payment_stage IN ('DEPOSIT','BALANCE_AND_SHIPPING'));
ALTER TABLE payment_records ADD CONSTRAINT chk_payment_positive CHECK(amount_vnd>0);
CREATE UNIQUE INDEX uq_paid_per_payment_stage ON payment_records(order_id,payment_stage) WHERE status='SIMULATED_PAID';
CREATE INDEX idx_payments_order_stage ON payment_records(order_id,payment_stage,created_at DESC);

CREATE TABLE cancellation_requests (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), order_id uuid NOT NULL REFERENCES orders(id),
 requested_by uuid NOT NULL REFERENCES users(id), reason_code varchar(50) NOT NULL,
 description text NOT NULL, status varchar(24) NOT NULL DEFAULT 'PENDING'
 CHECK(status IN ('PENDING','NEEDS_EVIDENCE','APPROVED','REJECTED','RESOLVED')),
 previous_order_status varchar(26) NOT NULL,
 decided_by uuid REFERENCES users(id), decided_at timestamptz, decision_reason text,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_open_cancellation_per_order ON cancellation_requests(order_id)
 WHERE status IN ('PENDING','NEEDS_EVIDENCE','APPROVED');
CREATE INDEX idx_cancellation_requested ON cancellation_requests(requested_by,created_at DESC);
CREATE TABLE cancellation_policies (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), code varchar(64) NOT NULL UNIQUE,
 policy_version integer NOT NULL CHECK(policy_version>0), description text NOT NULL,
 rules jsonb NOT NULL DEFAULT '{}'::jsonb, active boolean NOT NULL DEFAULT true,
 effective_from timestamptz NOT NULL DEFAULT now(), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE refund_settlements (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), order_id uuid NOT NULL REFERENCES orders(id),
 cancellation_request_id uuid REFERENCES cancellation_requests(id), dispute_id uuid REFERENCES disputes(id),
 policy_id uuid REFERENCES cancellation_policies(id), decided_by uuid NOT NULL REFERENCES users(id),
 paid_total_vnd bigint NOT NULL CHECK(paid_total_vnd>=0),
 retained_amount_vnd bigint NOT NULL CHECK(retained_amount_vnd>=0),
 refundable_amount_vnd bigint NOT NULL CHECK(refundable_amount_vnd>=0),
 reason_code varchar(60) NOT NULL, decision_reason text NOT NULL,
 status varchar(20) NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','APPROVED','PROCESSING','COMPLETED','CANCELLED')),
 decided_at timestamptz NOT NULL DEFAULT now(),
 CHECK(retained_amount_vnd+refundable_amount_vnd=paid_total_vnd),
 CHECK((cancellation_request_id IS NOT NULL) <> (dispute_id IS NOT NULL))
);
CREATE INDEX idx_refund_settlements_order ON refund_settlements(order_id,decided_at DESC);
CREATE TABLE refund_transactions (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), settlement_id uuid NOT NULL REFERENCES refund_settlements(id),
 amount_vnd bigint NOT NULL CHECK(amount_vnd>0), idempotency_key text NOT NULL UNIQUE,
 status varchar(24) NOT NULL DEFAULT 'SIMULATED_PENDING'
 CHECK(status IN ('SIMULATED_PENDING','SIMULATED_REFUNDED','SIMULATED_FAILED')),
 completed_at timestamptz, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_refund_transactions_settlement ON refund_transactions(settlement_id,created_at DESC);

-- Prepaid order cancellation, financial and inspection protection remain service-level invariants:
-- 1) Order creates deposit exactly matching generated deposit_amount_vnd.
-- 2) No READY_TO_SHIP unless one PAID deposit + one PAID balance transaction sum to total_vnd.
-- 3) Do not ship if refund/cancellation/dispute blocks progression.
-- 4) A seller cannot change an accepted offer or published description snapshot.
-- 5) An expired hold must be marked EXPIRED by a background job before releasing it.
-- 6) Releasing a product after CANCELLED requires verification it is physically resellable.
-- 7) Settlement refund must be <= actual successfully simulated payments minus prior refunds.
-- 8) Do not run mock payment endpoints in real-payment production mode.
CREATE INDEX idx_order_deposit_due ON orders(deposit_deadline) WHERE order_status='AWAITING_DEPOSIT';
CREATE INDEX idx_order_balance_due ON orders(balance_deadline) WHERE order_status='AWAITING_BALANCE';
CREATE INDEX idx_inspection_request_type ON inspection_requests(request_type,status,created_at DESC);
CREATE INDEX idx_conversations_buyer ON conversations(buyer_id,updated_at DESC);
CREATE INDEX idx_conversations_seller ON conversations(seller_id,updated_at DESC);

COMMIT;
