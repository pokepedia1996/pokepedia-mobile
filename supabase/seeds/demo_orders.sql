-- Demo orders for the Pesanan screen.
--
-- The app reads `orders` (buyer_id = auth.uid()) with its `order_items`,
-- each item's `settlements` row (that's where the condition and shipping
-- cost live) and the order's `shipments` row. This makes one of each in a
-- different state so the list, the status chips and the detail page all
-- have something to draw.
--
-- Run in the Supabase SQL editor. Everything it writes is tagged
-- `PKP-DEMO-…`, and the cleanup at the bottom removes exactly that.

DO $$
DECLARE
  v_buyer     uuid;
  v_seller    uuid;
  v_card      record;
  v_order_id  bigint;
  v_item_id   bigint;
  v_number    text;
  v_i         int := 0;
  -- order status | item status | shipped? | price | settlement status
  -- (settlement statuses come from `settlements_status_check`, which has no
  -- 'paid' — payment is recorded by `paid_at`, not the status.)
  v_states    text[][] := ARRAY[
    ['awaiting_shipment', 'accepted',  'no',  '185000', 'awaiting_shipment'],
    ['shipped',           'in_escrow', 'yes', '420000', 'shipped'],
    ['completed',         'completed', 'yes', '75000',  'completed']
  ];
BEGIN
  -- Buyer: change this address if you want the orders on another account.
  SELECT id INTO v_buyer FROM auth.users
   WHERE email = 'pudyastasatria@gmail.com';
  IF v_buyer IS NULL THEN
    RAISE EXCEPTION 'buyer not found — set the email above to your account';
  END IF;

  -- Seller: any other account, preferring one that actually has a shop, so
  -- the list shows a store name rather than a username.
  SELECT sp.user_id INTO v_seller
    FROM seller_profiles sp
   WHERE sp.user_id <> v_buyer
   LIMIT 1;
  IF v_seller IS NULL THEN
    SELECT p.id INTO v_seller FROM profiles p WHERE p.id <> v_buyer LIMIT 1;
  END IF;
  IF v_seller IS NULL THEN
    RAISE EXCEPTION 'need a second account to act as the seller';
  END IF;

  FOR v_card IN
    SELECT id FROM cards WHERE image_url IS NOT NULL ORDER BY id LIMIT 3
  LOOP
    v_i := v_i + 1;
    v_number := 'PKP-DEMO-' || to_char(now(), 'YYMMDD') || '-' || v_i;

    INSERT INTO orders (order_number, buyer_id, seller_id, status, created_at)
    VALUES (
      v_number, v_buyer, v_seller, v_states[v_i][1],
      now() - (v_i || ' days')::interval
    )
    RETURNING id INTO v_order_id;

    INSERT INTO order_items (
      order_id, order_number, bid_user_id, ask_user_id, card_id,
      match_price, matched_quantity, status, match_type, created_at
    )
    VALUES (
      v_order_id, v_number, v_buyer, v_seller, v_card.id,
      v_states[v_i][4]::int, v_i, v_states[v_i][2], 'cart_checkout',
      now() - (v_i || ' days')::interval
    )
    RETURNING id INTO v_item_id;

    -- Condition and shipping cost are read off the settlement, not the
    -- listing: a listing can close, and a closed one isn't readable by the
    -- buyer.
    INSERT INTO settlements (
      order_item_id, buyer_id, seller_id, status, escrow_amount,
      shipping_cost, payment_method, payment_deadline, paid_at, condition,
      quantity, courier_company, courier_service
    )
    VALUES (
      v_item_id, v_buyer, v_seller, v_states[v_i][5],
      v_states[v_i][4]::int * v_i, 18000, 'xendit',
      now() + interval '1 day', now() - (v_i || ' days')::interval,
      (ARRAY['NM','LP','MP'])[v_i], v_i, 'jne', 'REG'
    );

    IF v_states[v_i][3] = 'yes' THEN
      INSERT INTO shipments (
        order_id, status, tracking_number, courier, shipped_at
      )
      VALUES (
        v_order_id, 'shipped', 'JX' || (100000 + v_i) || 'ID', 'JNE Reguler',
        now() - (v_i || ' hours')::interval
      );
    END IF;

    RAISE NOTICE 'made % (%)', v_number, v_states[v_i][1];
  END LOOP;
END $$;

-- Cleanup — removes only what the block above wrote.
-- DELETE FROM settlements WHERE order_item_id IN (
--   SELECT id FROM order_items WHERE order_number LIKE 'PKP-DEMO-%');
-- DELETE FROM shipments WHERE order_id IN (
--   SELECT id FROM orders WHERE order_number LIKE 'PKP-DEMO-%');
-- DELETE FROM order_items WHERE order_number LIKE 'PKP-DEMO-%';
-- DELETE FROM orders WHERE order_number LIKE 'PKP-DEMO-%';
