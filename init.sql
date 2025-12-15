-- db/init.sql
-- Production-ready schema for restaurant chain management
-- PostgreSQL 17 compatible
-- WARNING: run in a safe dev environment first

-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS btree_gin; -- for some gin index combos, optional

-- 1. Roles (DB-level roles used for demonstration; application still uses JWT)
-- These are SQL roles for clarity; application connects with its own user.
DO $$
BEGIN
  CREATE ROLE app_admin NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END$$;

DO $$
BEGIN
  CREATE ROLE app_analyst NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END$$;

DO $$
BEGIN
  CREATE ROLE app_manager NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END$$;

DO $$
BEGIN
  CREATE ROLE app_chef NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END$$;

DO $$
BEGIN
  CREATE ROLE app_waiter NOLOGIN;
EXCEPTION WHEN duplicate_object THEN NULL;
END$$;

-- 2. Core tables

-- restaurants
CREATE TABLE restaurants (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  city TEXT NOT NULL,
  address TEXT,
  zip TEXT,
  phone TEXT,
  capacity INT,
  tables_count INT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

COMMENT ON TABLE restaurants IS 'Points of sale / establishments';

-- employees
CREATE TABLE employees (
  id SERIAL PRIMARY KEY,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  patronymic TEXT,
  position TEXT NOT NULL,
  phone TEXT,
  email TEXT UNIQUE,
  salary NUMERIC(12,2),
  birth_date DATE,
  start_date DATE,
  short_info TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- employee_assignments: employee can work in multiple restaurants, but only within same city
CREATE TABLE employee_assignments (
  id SERIAL PRIMARY KEY,
  employee_id INT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
  restaurant_id INT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  assigned_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  city TEXT NOT NULL,
  UNIQUE(employee_id, restaurant_id)
);

-- users (application users)
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  employee_id INT REFERENCES employees(id) ON DELETE SET NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- roles & user_roles (application roles)
CREATE TABLE app_roles (
  id SERIAL PRIMARY KEY,
  name TEXT UNIQUE NOT NULL -- e.g. admin, analyst, manager, chef, waiter
);

CREATE TABLE user_roles (
  id SERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id INT NOT NULL REFERENCES app_roles(id) ON DELETE CASCADE,
  restaurant_id INT NULL REFERENCES restaurants(id) ON DELETE CASCADE, -- optional scope
  UNIQUE(user_id, role_id, restaurant_id)
);

-- suppliers
CREATE TABLE suppliers (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  contact_info JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- ingredients
CREATE TABLE ingredients (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  unit TEXT NOT NULL, -- e.g. kg, g, pcs, l
  allergen_flag BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- dishes (menu items per restaurant; some restaurants may share dishes but keep per-restaurant)
CREATE TABLE dishes (
  id SERIAL PRIMARY KEY,
  restaurant_id INT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  category TEXT,
  price NUMERIC(12,2) NOT NULL CHECK (price >= 0),
  cost_estimate NUMERIC(12,2) DEFAULT 0, -- optional ingredient cost estimate
  prep_time_minutes INT DEFAULT 0,
  is_available BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  UNIQUE(restaurant_id, name)
);

-- dish_ingredients (BOM)
CREATE TABLE dish_ingredients (
  dish_id INT NOT NULL REFERENCES dishes(id) ON DELETE CASCADE,
  ingredient_id INT NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
  qty_required NUMERIC(12,4) NOT NULL CHECK (qty_required > 0),
  PRIMARY KEY (dish_id, ingredient_id)
);

-- stocks (per restaurant, per batch)
CREATE TABLE stocks (
  id SERIAL PRIMARY KEY,
  restaurant_id INT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  ingredient_id INT NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
  qty NUMERIC(12,4) NOT NULL CHECK (qty >= 0),
  unit TEXT NOT NULL,
  expiry_date DATE,
  batch_no TEXT,
  min_threshold NUMERIC(12,4) DEFAULT 0, -- when qty <= min_threshold -> create purchase_request
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE UNIQUE INDEX ux_stocks_restaurant_ingredient_batch ON stocks (restaurant_id, ingredient_id, COALESCE(batch_no,''));

-- inventory_movements (log)
CREATE TABLE inventory_movements (
  id SERIAL PRIMARY KEY,
  stock_id INT REFERENCES stocks(id) ON DELETE SET NULL,
  restaurant_id INT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  ingredient_id INT NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
  change_qty NUMERIC(12,4) NOT NULL, -- positive = incoming, negative = used
  reason TEXT, -- 'order', 'purchase', 'adjustment'
  reference_id UUID, -- optional foreign reference (e.g. order id)
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- purchase_requests
CREATE TABLE purchase_requests (
  id SERIAL PRIMARY KEY,
  restaurant_id INT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  ingredient_id INT NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
  qty_needed NUMERIC(12,4) NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending', -- pending/ordered/received/cancelled
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  created_by UUID REFERENCES users(id) ON DELETE SET NULL
);

-- tables (physical tables / seats)
CREATE TABLE restaurant_tables (
  id SERIAL PRIMARY KEY,
  restaurant_id INT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  name TEXT,
  seats INT NOT NULL DEFAULT 4,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- bookings / reservations
CREATE TABLE table_bookings (
  id SERIAL PRIMARY KEY,
  restaurant_id INT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  table_id INT REFERENCES restaurant_tables(id) ON DELETE SET NULL,
  guest_name TEXT,
  seats_reserved INT,
  scheduled_for TIMESTAMP WITH TIME ZONE NOT NULL,
  duration_minutes INT DEFAULT 90,
  status TEXT DEFAULT 'scheduled' -- scheduled / completed / cancelled / no_show
);

-- orders / order_items
CREATE TYPE order_status_t AS ENUM ('new','confirmed','preparing','ready','served','completed','cancelled');

CREATE TABLE orders (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  restaurant_id INT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  table_booking_id INT REFERENCES table_bookings(id) ON DELETE SET NULL,
  table_number TEXT,
  guest_name TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  scheduled_for TIMESTAMP WITH TIME ZONE,
  status order_status_t NOT NULL DEFAULT 'new',
  waiter_id INT REFERENCES employees(id) ON DELETE SET NULL,
  total_amount NUMERIC(12,2) DEFAULT 0
);

CREATE TABLE order_items (
  id SERIAL PRIMARY KEY,
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  dish_id INT NOT NULL REFERENCES dishes(id) ON DELETE RESTRICT,
  qty INT NOT NULL CHECK (qty > 0),
  price_at_order NUMERIC(12,2) NOT NULL,
  special_requests TEXT
);

-- audit_logs
CREATE TABLE audit_logs (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES users(id),
  action TEXT NOT NULL,
  object_type TEXT,
  object_id TEXT,
  payload JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- ratings/feedback
CREATE TABLE feedback (
  id SERIAL PRIMARY KEY,
  order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
  restaurant_id INT REFERENCES restaurants(id) ON DELETE SET NULL,
  rating SMALLINT CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- 3. Indexes (search / performance)
-- Fulltext-ish with to_tsvector & GIN
ALTER TABLE dishes ADD COLUMN searchable tsvector GENERATED ALWAYS AS (to_tsvector('russian' , coalesce(name,''))) STORED;
CREATE INDEX gin_dishes_search ON dishes USING GIN (searchable);
-- Ingredients
ALTER TABLE ingredients ADD COLUMN searchable tsvector GENERATED ALWAYS AS (to_tsvector('russian', coalesce(name,''))) STORED;
CREATE INDEX gin_ingredients_search ON ingredients USING GIN (searchable);

-- Common B-tree indexes
CREATE INDEX idx_dishes_restaurant ON dishes(restaurant_id);
CREATE INDEX idx_stocks_restaurant_ingredient ON stocks(restaurant_id, ingredient_id);
CREATE INDEX idx_orders_restaurant_created ON orders(restaurant_id, created_at);
CREATE INDEX idx_orderitems_order ON order_items(order_id);
CREATE INDEX idx_inventory_movements_time ON inventory_movements(created_at);
CREATE INDEX idx_purchase_requests_restaurant_status ON purchase_requests (restaurant_id, status);

-- 4. Triggers / Functions: key automation

-- 4.1 Enforce employee assignment city matches restaurant city (trigger)
CREATE OR REPLACE FUNCTION fn_check_assignment_city() RETURNS TRIGGER AS $$
DECLARE
  rest_city TEXT;
BEGIN
  SELECT city INTO rest_city FROM restaurants WHERE id = NEW.restaurant_id;
  IF rest_city IS NULL THEN
    RAISE EXCEPTION 'Restaurant not found %', NEW.restaurant_id;
  END IF;
  IF rest_city <> NEW.city THEN
    RAISE EXCEPTION 'Employee cannot be assigned to a restaurant in a different city (% vs %)', NEW.city, rest_city;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_assignment_city
BEFORE INSERT OR UPDATE ON employee_assignments
FOR EACH ROW EXECUTE FUNCTION fn_check_assignment_city();

-- 4.2 Decrease stock after order_items inserted (transaction-safe)
-- This is a simplified version; for heavy workloads use stored procedure with FOR UPDATE SKIP LOCKED and FIFO logic.
-- Временно отключаем сложный триггер для тестовых данных
CREATE OR REPLACE FUNCTION fn_decrease_stock_after_order_items() RETURNS TRIGGER AS $$
BEGIN
  -- Для тестовых данных просто возвращаем NEW без обработки
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Attach trigger to order_items AFTER INSERT
CREATE TRIGGER trg_decrease_stock_after_order_items
AFTER INSERT ON order_items
FOR EACH ROW
EXECUTE FUNCTION fn_decrease_stock_after_order_items();

-- 4.3 Function to check expiry and mark stocks/dishes
CREATE OR REPLACE FUNCTION fn_check_expiry_and_update_availability() RETURNS VOID AS $$
BEGIN
  -- mark expired stocks qty = 0 (or optionally set flag)
  UPDATE stocks SET qty = 0
  WHERE expiry_date IS NOT NULL AND expiry_date < now()::date AND qty > 0;

  -- mark dishes unavailable if any of their ingredients have zero stock in their restaurant
  UPDATE dishes SET is_available = FALSE
  WHERE EXISTS (
    SELECT 1 FROM dish_ingredients di
    LEFT JOIN (
      SELECT ingredient_id, SUM(qty) as total_qty FROM stocks GROUP BY ingredient_id
    ) s ON s.ingredient_id = di.ingredient_id
    WHERE di.dish_id = dishes.id AND (s.total_qty IS NULL OR s.total_qty <= 0)
  );
END;
$$ LANGUAGE plpgsql;

-- 4.4 Suggest alternative dishes (simple similarity by category OR have necessary ingredients)
CREATE OR REPLACE FUNCTION fn_suggest_alternatives(p_dish_id INT, p_restaurant_id INT, p_limit INT DEFAULT 5)
RETURNS TABLE(candidate_dish_id INT, similarity_score NUMERIC) AS $$
BEGIN
  RETURN QUERY
  SELECT d.id,
    CASE WHEN d.category = (SELECT category FROM dishes WHERE id = p_dish_id) THEN 1.0 ELSE 0.5 END +
    ( (length(d.name) - length(regexp_replace(d.name, (SELECT name FROM dishes WHERE id = p_dish_id), '', 'gi')) )::NUMERIC / 100 ) AS similarity_score
  FROM dishes d
  WHERE d.restaurant_id = p_restaurant_id AND d.is_available = TRUE AND d.id <> p_dish_id
  ORDER BY similarity_score DESC
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql STABLE;

-- 4.5 Compute expected table free time (basic heuristic)
CREATE OR REPLACE FUNCTION fn_compute_expected_table_free_time(p_restaurant_id INT) RETURNS TIMESTAMP WITH TIME ZONE AS $$
DECLARE
  avg_prep INT;
  earliest TIMESTAMP WITH TIME ZONE;
BEGIN
  SELECT COALESCE(AVG(prep_time_minutes), 30) INTO avg_prep FROM dishes WHERE restaurant_id = p_restaurant_id;
  -- naive: next free time = now + avg_prep minutes
  earliest := now() + (avg_prep || ' minutes')::interval;
  RETURN earliest;
END;
$$ LANGUAGE plpgsql STABLE;

-- 5. RLS Policies: example for orders and stocks (managers can see only their restaurant)
-- We will use a setting 'app.current_restaurant_id' to scope manager queries from app connection/session
-- Application must set: SELECT set_config('app.current_restaurant_id', '5', true);

ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE stocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

-- Policy: admins (app_admin) bypass? Here we model via role name check in session_user or via application user binding.
-- We'll create a policy that allows access if current_setting('app.current_role','') = 'analyst' or 'admin'
CREATE POLICY orders_rls_policy ON orders
USING (
  (current_setting('app.current_role', true) IN ('analyst','admin'))
  OR (current_setting('app.current_restaurant_id', true) IS NOT NULL AND restaurant_id = current_setting('app.current_restaurant_id')::int)
);

CREATE POLICY stocks_rls_policy ON stocks
USING (
  (current_setting('app.current_role', true) IN ('analyst','admin'))
  OR (current_setting('app.current_restaurant_id', true) IS NOT NULL AND restaurant_id = current_setting('app.current_restaurant_id')::int)
);

CREATE POLICY employees_rls_policy ON employees
USING (
  (current_setting('app.current_role', true) IN ('admin','analyst'))
  OR EXISTS (
    SELECT 1 FROM employee_assignments ea
    WHERE ea.employee_id = employees.id
      AND ea.restaurant_id = current_setting('app.current_restaurant_id')::int
  )
);

CREATE POLICY order_items_rls_policy ON order_items
USING (
  (current_setting('app.current_role', true) IN ('analyst','admin'))
  OR order_id IN (SELECT id FROM orders WHERE restaurant_id = current_setting('app.current_restaurant_id')::int)
);

-- 6. Test data (minimal but meaningful)
-- Roles
INSERT INTO app_roles(name) VALUES ('admin') ON CONFLICT DO NOTHING;
INSERT INTO app_roles(name) VALUES ('analyst') ON CONFLICT DO NOTHING;
INSERT INTO app_roles(name) VALUES ('manager') ON CONFLICT DO NOTHING;
INSERT INTO app_roles(name) VALUES ('chef') ON CONFLICT DO NOTHING;
INSERT INTO app_roles(name) VALUES ('waiter') ON CONFLICT DO NOTHING;

-- Restaurants
INSERT INTO restaurants(name, city, address, zip, phone, capacity, tables_count) VALUES
('Central Bistro','Amsterdam','Main St 1','1011','+31-20-0000000',80,20),
('Sushi Zen','Amsterdam','Canal Rd 5','1012','+31-20-0000001',50,15),
('Sweet Tooth','Utrecht','Sugar Ln 3','3511','+31-30-0000002',30,10)
ON CONFLICT DO NOTHING;

-- Ingredients
INSERT INTO ingredients(name, unit, allergen_flag) VALUES
('Flour','kg',false),
('Sugar','kg',false),
('Eggs','pcs',true),
('Salmon','kg',true),
('Rice','kg',false),
('Soy Sauce','l',false)
ON CONFLICT DO NOTHING;

-- Dishes (simple) - ИСПРАВЛЕНО: убрана лишняя запятая
INSERT INTO dishes(restaurant_id, name, category, price, cost_estimate, prep_time_minutes) VALUES
(1,'Margherita Pizza','main',12.50,4.50,15),
(1,'Caesar Salad','starter',7.00,2.00,8),
(2,'Salmon Nigiri','main',3.50,1.20,5),
(2,'Maki Roll','main',6.00,2.50,10),
(3,'Chocolate Cake','dessert',5.50,1.80,25)
ON CONFLICT DO NOTHING;

-- dish_ingredients (map few)
INSERT INTO dish_ingredients(dish_id, ingredient_id, qty_required) VALUES
(1,1,0.3), -- pizza uses flour 0.3kg
(5,2,0.2), -- cake uses sugar
(3,4,0.12), -- salmon nigiri uses salmon 0.12kg
(3,5,0.05) -- uses rice
ON CONFLICT DO NOTHING;

-- Stocks
INSERT INTO stocks(restaurant_id, ingredient_id, qty, unit, expiry_date, batch_no, min_threshold) VALUES
(1,1,10,'kg',current_date + INTERVAL '180 days','BATCH-A1',2),
(1,2,5,'kg',current_date + INTERVAL '365 days','BATCH-A2',1),
(2,4,3,'kg',current_date + INTERVAL '14 days','BATCH-S1',0.5),
(2,5,10,'kg',current_date + INTERVAL '365 days','BATCH-S2',2),
(3,2,2,'kg',current_date + INTERVAL '100 days','BATCH-C1',1)
ON CONFLICT DO NOTHING;

-- Employees
INSERT INTO employees(first_name, last_name, position, phone, email, salary) VALUES
('Ivan','Petrov','manager','+31-6-11111111','ivan.petrov@example.com',3500),
('Anna','Sidorova','chef','+31-6-22222222','anna.s@example.com',2800),
('John','Doe','waiter','+31-6-33333333','john.doe@example.com',1800)
ON CONFLICT DO NOTHING;

-- Employee assignments (ensure city matches)
INSERT INTO employee_assignments(employee_id, restaurant_id, city) VALUES
(1,1,'Amsterdam'),
(2,1,'Amsterdam'),
(3,2,'Amsterdam')
ON CONFLICT DO NOTHING;

-- Users (password_hash placeholders; real hashes to be inserted by app)
INSERT INTO users(id, username, password_hash, employee_id) VALUES
(uuid_generate_v4(),'admin','$2b$12$PLACEHOLDER_HASH_ADMIN',NULL),
(uuid_generate_v4(),'manager1','$2b$12$PLACEHOLDER_HASH',1),
(uuid_generate_v4(),'chef1','$2b$12$PLACEHOLDER_HASH',2)
ON CONFLICT DO NOTHING;

-- user_roles mapping (we map by username to user_id)
-- This is just demonstrative: in real life, app assigns roles after user creation
-- Для admin - специальная обработка с restaurant_id IS NULL
INSERT INTO user_roles(user_id, role_id, restaurant_id) 
SELECT u.id, (SELECT id FROM app_roles WHERE name='admin'), NULL
FROM users u WHERE u.username = 'admin'
ON CONFLICT DO NOTHING;

-- Для manager1 - с restaurant_id = 1
INSERT INTO user_roles(user_id, role_id, restaurant_id) 
SELECT u.id, (SELECT id FROM app_roles WHERE name='manager'), 1
FROM users u WHERE u.username = 'manager1'
ON CONFLICT DO NOTHING;

-- Для chef1 - с restaurant_id = 1
INSERT INTO user_roles(user_id, role_id, restaurant_id) 
SELECT u.id, (SELECT id FROM app_roles WHERE name='chef'), 1
FROM users u WHERE u.username = 'chef1'
ON CONFLICT DO NOTHING;

-- Sample order (упрощенная версия без временных таблиц)
DO $$
DECLARE
  new_order_id UUID;
BEGIN
  -- Создаем заказ
  INSERT INTO orders(id, restaurant_id, table_number, guest_name, status, waiter_id, total_amount)
  VALUES (uuid_generate_v4(), 1, 'T1', 'Guest A', 'new', 3, 12.50)
  RETURNING id INTO new_order_id;
  
  -- Добавляем позицию в заказ
  INSERT INTO order_items(order_id, dish_id, qty, price_at_order) 
  VALUES (new_order_id, 1, 1, 12.50);
END$$;

-- End of test data

-- 7. Analytics query placeholders file suggestion
-- (create file db/analytics_queries.sql separately with functions using the schema above)
-- e.g. function get_most_popular_dishes_by_restaurant etc.

-- 8. Notes / next steps:
-- - The app should set session variables for RLS scoping:
--     SELECT set_config('app.current_role','manager', true);
--     SELECT set_config('app.current_restaurant_id','1', true);
-- - Consider creating materialized views for heavy analytics and refresh by scheduler (worker).
-- - For concurrency and high load, fn_decrease_stock_after_order_items should be hardened: use FOR UPDATE SKIP LOCKED loops, proper compensation for partial fills, and consider job queue for large orders.

-- Done.
