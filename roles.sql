-- =====================================================
-- ROLES AND PRIVILEGES FOR RESTAURANT SYSTEM
-- =====================================================

-- ---------- 1. Create PostgreSQL roles (groups) ----------
CREATE ROLE role_admin NOLOGIN;
CREATE ROLE role_analyst NOLOGIN;
CREATE ROLE role_manager NOLOGIN;
CREATE ROLE role_cook NOLOGIN;
CREATE ROLE role_waiter NOLOGIN;

-- ---------- 2. Create technical application user ----------
CREATE ROLE app_user LOGIN PASSWORD 'strong_password';

-- ---------- 3. Grant roles to technical user ----------
GRANT role_admin, role_analyst, role_manager, role_cook, role_waiter TO app_user;

-- ---------- 4. Grant privileges to roles ----------

-- Admin: full access
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO role_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO role_admin;

-- Analyst: read-only
GRANT SELECT ON
cities, restaurants, restaurant_tables,
employees, employee_assignments,
dishes, dish_ingredients, dish_price_history,
orders, order_items,
ingredients, ingredient_batches, inventory_movements, purchase_requests,
suppliers, reservations, feedbacks, audit_logs
TO role_analyst;

-- Manager: orders & inventory in own restaurant
GRANT SELECT, INSERT, UPDATE ON
orders, order_items, reservations, purchase_requests
TO role_manager;

GRANT SELECT, INSERT, UPDATE ON
ingredient_batches, inventory_movements
TO role_manager;

-- Cook: view orders & ingredients, request purchase
GRANT SELECT ON
orders, order_items, dishes, dish_ingredients
TO role_cook;

GRANT SELECT ON
ingredients, ingredient_batches
TO role_cook;

GRANT INSERT ON purchase_requests TO role_cook;

-- Waiter: create orders, view menu
GRANT SELECT ON dishes TO role_waiter;
GRANT SELECT, INSERT ON orders, order_items TO role_waiter;
GRANT UPDATE (status) ON orders TO role_waiter;

-- ---------- 5. Optional: RLS setup reminder ----------
-- RLS policies should be enabled on tables and will use
-- current_setting('app.role') and current_setting('app.restaurant_id')
-- to restrict access per role and per restaurant
