-- Подключаем расширения
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; --генерация uuid
CREATE EXTENSION IF NOT EXISTS pg_trgm; -- для полнотекстового поиска
CREATE EXTENSION IF NOT EXISTS btree_gin; -- позволяет использовать GIN-индексы с обычными операторами

-- =========================
-- Схема справочники. Создаёт основную географическую и физическую структуру сети ресторанов.
CREATE TABLE cities (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE restaurants (
    id SERIAL PRIMARY KEY,
    city_id INT NOT NULL REFERENCES cities(id),
    name TEXT NOT NULL,
    address TEXT,
    postal_code TEXT,
    phone TEXT,
    capacity INT DEFAULT 0,
    tables_count INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Столы/места (для расчета занятости/ETA)
CREATE TABLE restaurant_tables (
    id SERIAL PRIMARY KEY,
    restaurant_id INT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    table_number TEXT NOT NULL,
    seats INT NOT NULL DEFAULT 4,
    UNIQUE (restaurant_id, table_number)
);

-- =========================
-- Сотрудники и их назначения
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    full_name TEXT NOT NULL,
    position TEXT NOT NULL,
    phone TEXT,
    email TEXT UNIQUE,
    experience_years INT,
    age INT,
    salary NUMERIC(12,2),
    description TEXT,
    hired_at DATE
);

-- сотрудник может работать в нескольких заведениях, но только в одном городе:
CREATE TABLE employee_assignments (
    id SERIAL PRIMARY KEY,
    employee_id INT NOT NULL REFERENCES employees(id) ON DELETE CASCADE,
    restaurant_id INT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    assigned_from TIMESTAMP WITH TIME ZONE DEFAULT now(),
    assigned_to TIMESTAMP WITH TIME ZONE,
    CHECK (assigned_from <= COALESCE(assigned_to, 'infinity'::timestamp))
);

-- триггер, который гарантирует, что сотрудник не может работать в ресторанах из разных городов.
CREATE OR REPLACE FUNCTION fn_check_employee_assignments_city()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    rest_city INT;
BEGIN
    SELECT city_id INTO rest_city FROM restaurants WHERE id = NEW.restaurant_id;
    IF EXISTS (
        SELECT 1 FROM employee_assignments ea
        JOIN restaurants r ON ea.restaurant_id = r.id
        WHERE ea.employee_id = NEW.employee_id AND r.city_id <> rest_city AND ea.id <> NEW.id
    ) THEN
        RAISE EXCEPTION 'Employee % already assigned to a restaurant in a different city', NEW.employee_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_employee_assignments_city
BEFORE INSERT OR UPDATE ON employee_assignments
FOR EACH ROW EXECUTE FUNCTION fn_check_employee_assignments_city();

-- =========================
-- Пользователи и роли (безопасность)
-- users: логины/хеши паролей. Хеширование производится в приложении (bcrypt/argon2).
CREATE TABLE app_users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    employee_id INT REFERENCES employees(id),
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TABLE app_roles (
    id SERIAL PRIMARY KEY,
    name TEXT UNIQUE NOT NULL
);

INSERT INTO app_roles (name) VALUES ('admin') ON CONFLICT DO NOTHING;
INSERT INTO app_roles (name) VALUES ('analyst') ON CONFLICT DO NOTHING;
INSERT INTO app_roles (name) VALUES ('manager') ON CONFLICT DO NOTHING;
INSERT INTO app_roles (name) VALUES ('cook') ON CONFLICT DO NOTHING;
INSERT INTO app_roles (name) VALUES ('waiter') ON CONFLICT DO NOTHING;

CREATE TABLE app_user_roles (
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    role_id INT NOT NULL REFERENCES app_roles(id) ON DELETE CASCADE,
    restaurant_id INT REFERENCES restaurants(id),
    PRIMARY KEY (user_id, role_id)
);


--=========================
-- Ингридиенты и склад
CREATE TABLE suppliers ( -- поставщики
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    phone TEXT,
    contact_person TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Справочник ингредиентов
CREATE TABLE ingredients (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    unit TEXT,                 -- например: g, kg, pcs, l
    allergen BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- партии на складе (с количеством, сроком годности, активностью).
CREATE TABLE ingredient_batches (
    id SERIAL PRIMARY KEY,
    ingredient_id INT NOT NULL REFERENCES ingredients(id) ON DELETE CASCADE,
    restaurant_id INT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    supplier_id INT REFERENCES suppliers(id),
    batch_no TEXT,
    qty NUMERIC(12,4) NOT NULL DEFAULT 0,
    unit TEXT,
    price_per_unit NUMERIC(12,4),
    received_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    expiry_date DATE,
    active BOOLEAN DEFAULT TRUE,
    min_threshold NUMERIC(12,4) DEFAULT 0
);

-- индекс для быстрого поиска партий по ingredient и expiry
CREATE INDEX idx_batches_ingredient_restaurant_expiry ON ingredient_batches (ingredient_id, restaurant_id, expiry_date);

-- Движение на складе (для аудита)
CREATE TABLE inventory_movements (
    id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES ingredient_batches(id),
    ingredient_id INT REFERENCES ingredients(id),
    restaurant_id INT REFERENCES restaurants(id),
    change_qty NUMERIC(12,4) NOT NULL,
    reason TEXT,              -- 'order', 'manual_adjust', 'purchase_receipt'
    related_order_id INT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Запросы на покупку
CREATE TABLE purchase_requests (
    id SERIAL PRIMARY KEY,
    restaurant_id INT REFERENCES restaurants(id),
    ingredient_id INT REFERENCES ingredients(id),
    qty NUMERIC(12,4) NOT NULL,
    status TEXT NOT NULL DEFAULT 'new', -- new, ordered, received, cancelled
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- ============= БЛЮДА И МЕНЮ =============
-- блюда с ценой, категорией и флагом доступности
CREATE TABLE dishes (
    id SERIAL PRIMARY KEY,
    restaurant_id INT NOT NULL REFERENCES restaurants(id),
    name TEXT NOT NULL,
    category TEXT,
    price NUMERIC(12,2) NOT NULL,
    prep_time_minutes INT,
    is_available BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- состав блюда: сколько каждого ингредиента требуется
CREATE TABLE dish_ingredients (
    dish_id INT NOT NULL REFERENCES dishes(id) ON DELETE CASCADE,
    ingredient_id INT NOT NULL REFERENCES ingredients(id),
    qty_required NUMERIC(12,4) NOT NULL, -- в unit ингредиента
    PRIMARY KEY (dish_id, ingredient_id)
);

-- индекс для быстрого поиска блюд по названию (GIN + pg_trgm)
CREATE INDEX idx_dishes_name_gin ON dishes USING gin (name gin_trgm_ops);
CREATE INDEX idx_ingredients_name_gin ON ingredients USING gin (name gin_trgm_ops);

-- опциональная история изменения цен блюд
CREATE TABLE dish_price_history (
    id SERIAL PRIMARY KEY,
    dish_id INT REFERENCES dishes(id),
    price NUMERIC(12,2),
    valid_from TIMESTAMP WITH TIME ZONE DEFAULT now(),
    valid_to TIMESTAMP WITH TIME ZONE
);

-- ============= ЗАКАЗЫ, СТАТУСЫ, ITEM'ы =============
-- заказы с привязкой к ресторану, столу, гостю, времени и статусу
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    restaurant_id INT NOT NULL REFERENCES restaurants(id),
    table_id INT REFERENCES restaurant_tables(id),
    guest_name TEXT,
    created_by_user UUID REFERENCES app_users(id),
    order_time TIMESTAMP WITH TIME ZONE DEFAULT now(),
    scheduled_for TIMESTAMP WITH TIME ZONE,
    status TEXT NOT NULL DEFAULT 'created',
    accepted_at TIMESTAMP WITH TIME ZONE,
    preparing_at TIMESTAMP WITH TIME ZONE,
    ready_at TIMESTAMP WITH TIME ZONE,
    served_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    cancelled_at TIMESTAMP WITH TIME ZONE,
    total_amount NUMERIC(12,2) DEFAULT 0,
    is_finalized BOOLEAN NOT NULL DEFAULT FALSE
);

-- позиции заказа: блюда, количество, цена на момент заказа
CREATE TABLE order_items (
    id SERIAL PRIMARY KEY,
    order_id INT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    dish_id INT NOT NULL REFERENCES dishes(id),
    qty INT NOT NULL CHECK (qty > 0),
    price_at_order NUMERIC(12,2) NOT NULL,
    special_requests TEXT
);

-- ================== Пересчёт суммы заказа ==================
-- пересчитывает сумму заказа
CREATE OR REPLACE FUNCTION fn_recalc_order_total(p_order_id INT)
RETURNS VOID LANGUAGE sql AS $$
    UPDATE orders
    SET total_amount = COALESCE((
        SELECT SUM(qty * price_at_order)
        FROM order_items
        WHERE order_id = p_order_id
    ), 0)
    WHERE id = p_order_id;
$$;


CREATE INDEX idx_orders_restaurant_time ON orders (restaurant_id, order_time);

-- ============= ОТЗЫВЫ И ОЦЕНКИ =============
--  оценки и комментарии к заказам.
CREATE TABLE feedbacks (
    id SERIAL PRIMARY KEY,
    order_id INT REFERENCES orders(id),
    rating INT CHECK (rating >= 1 AND rating <= 5),
    comment TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

--  журнал всех действий пользователей (для безопасности и отладки).
CREATE TABLE audit_logs (
    id SERIAL PRIMARY KEY,
    user_id UUID,
    action_type TEXT,
    table_name TEXT,
    row_data JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- ============= БРОНИРОВАНИЯ (reservations) =============
CREATE TABLE reservations (
    id SERIAL PRIMARY KEY,
    restaurant_id INT NOT NULL REFERENCES restaurants(id),
    table_id INT REFERENCES restaurant_tables(id),
    guest_name TEXT,
    reserved_from TIMESTAMP WITH TIME ZONE NOT NULL,
    reserved_to TIMESTAMP WITH TIME ZONE NOT NULL,
    status TEXT DEFAULT 'booked' -- booked, cancelled, no_show, completed
);

-- ============= ФУНКЦИИ: автоматизации =============
-- Вспомогательная: суммарный остаток ингредиента в ресторане (по активным партиям)
CREATE OR REPLACE FUNCTION fn_total_ingredient_qty(p_ingredient_id INT, p_restaurant_id INT)
RETURNS NUMERIC LANGUAGE sql AS $$
    SELECT COALESCE(SUM(qty),0) FROM ingredient_batches
    WHERE ingredient_id = p_ingredient_id AND restaurant_id = p_restaurant_id AND active = TRUE;
$$;

-- Обновляет is_available у блюд
CREATE OR REPLACE FUNCTION fn_update_dishes_availability_for_restaurant(p_restaurant_id INT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    rec_dish RECORD;
    missing_count INT;
BEGIN
    FOR rec_dish IN SELECT * FROM dishes WHERE restaurant_id = p_restaurant_id
    LOOP
        SELECT COUNT(*) INTO missing_count
        FROM dish_ingredients di
        LEFT JOIN (
            SELECT ingredient_id, SUM(qty) AS total_qty
            FROM ingredient_batches
            WHERE restaurant_id = p_restaurant_id AND active = TRUE
            GROUP BY ingredient_id
        ) ib ON di.ingredient_id = ib.ingredient_id
        WHERE di.dish_id = rec_dish.id AND COALESCE(ib.total_qty,0) < di.qty_required;

        UPDATE dishes SET is_available = (missing_count = 0) WHERE id = rec_dish.id;
    END LOOP;
END;
$$;

-- Списывает ингредиенты при финализации заказа (использует min_threshold из партий)
CREATE OR REPLACE FUNCTION fn_decrease_stock_for_order(p_order_id INT)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
    rec_item RECORD;
    rec_recipe RECORD;
    v_needed NUMERIC;
    v_batch RECORD;
    v_left NUMERIC;
    v_total_left NUMERIC;
    v_min_threshold NUMERIC;
    v_restaurant_id INT;
BEGIN
    -- Получаем restaurant_id один раз
    SELECT restaurant_id INTO v_restaurant_id FROM orders WHERE id = p_order_id;

    -- Для всех позиций заказа
    FOR rec_item IN SELECT * FROM order_items WHERE order_id = p_order_id
    LOOP
        -- Для всех ингредиентов блюда
        FOR rec_recipe IN SELECT * FROM dish_ingredients WHERE dish_id = rec_item.dish_id
        LOOP
            v_needed := rec_recipe.qty_required * rec_item.qty;

            -- Списываем партии FIFO (expiry asc, earliest first)
            LOOP
                IF v_needed <= 0 THEN
                    EXIT;
                END IF;

                SELECT * INTO v_batch FROM ingredient_batches
                WHERE ingredient_id = rec_recipe.ingredient_id
                  AND restaurant_id = v_restaurant_id
                  AND active = TRUE
                  AND qty > 0
                ORDER BY COALESCE(expiry_date, 'infinity') ASC
                FOR UPDATE
                LIMIT 1;

                IF NOT FOUND THEN
                    RAISE EXCEPTION 'Not enough ingredient % for restaurant % needed %',
                        rec_recipe.ingredient_id, v_restaurant_id, v_needed;
                END IF;

                IF v_batch.qty >= v_needed THEN
                    UPDATE ingredient_batches SET qty = qty - v_needed WHERE id = v_batch.id;
                    INSERT INTO inventory_movements (batch_id, ingredient_id, restaurant_id, change_qty, reason, related_order_id)
                    VALUES (v_batch.id, rec_recipe.ingredient_id, v_restaurant_id, -v_needed, 'order', p_order_id);
                    v_needed := 0;
                ELSE
                    v_left := v_batch.qty;
                    UPDATE ingredient_batches SET qty = 0, active = FALSE WHERE id = v_batch.id;
                    INSERT INTO inventory_movements (batch_id, ingredient_id, restaurant_id, change_qty, reason, related_order_id)
                    VALUES (v_batch.id, rec_recipe.ingredient_id, v_restaurant_id, -v_left, 'order', p_order_id);
                    v_needed := v_needed - v_left;
                END IF;
            END LOOP;

            -- Получаем минимальный порог для этого ингредиента в ресторане
            SELECT COALESCE(MIN(min_threshold), 5) INTO v_min_threshold
            FROM ingredient_batches
            WHERE ingredient_id = rec_recipe.ingredient_id
              AND restaurant_id = v_restaurant_id;

            -- Проверяем общий остаток по ингредиенту
            SELECT COALESCE(SUM(qty), 0) INTO v_total_left
            FROM ingredient_batches
            WHERE ingredient_id = rec_recipe.ingredient_id
              AND restaurant_id = v_restaurant_id
              AND active = TRUE;

            -- Если остаток <= порога — создаём заявку
            IF v_total_left <= v_min_threshold THEN
                IF NOT EXISTS (
                    SELECT 1 FROM purchase_requests
                    WHERE restaurant_id = v_restaurant_id
                      AND ingredient_id = rec_recipe.ingredient_id
                      AND status IN ('new','ordered')
                ) THEN
                    INSERT INTO purchase_requests (restaurant_id, ingredient_id, qty, status)
                    VALUES (v_restaurant_id, rec_recipe.ingredient_id, v_min_threshold * 10, 'new');
                END IF;
            END IF;
        END LOOP;
    END LOOP;

    -- Обновляем доступность блюд
    PERFORM fn_update_dishes_availability_for_restaurant(v_restaurant_id);
END;
$$;

-- Завершает заказ (вызывает списание)
CREATE OR REPLACE FUNCTION fn_finalize_order(p_order_id INT)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    -- защита от повторной финализации
    IF EXISTS (
        SELECT 1 FROM orders
        WHERE id = p_order_id AND is_finalized = TRUE
    ) THEN
        RAISE EXCEPTION 'Order % already finalized', p_order_id;
    END IF;

    -- списание ингредиентов (основная бизнес-логика)
    PERFORM fn_decrease_stock_for_order(p_order_id);

    -- финальное состояние заказа
    UPDATE orders
    SET is_finalized = TRUE,
        status = 'completed',
        completed_at = now()
    WHERE id = p_order_id;
END;
$$;


-- Функция, которая помечает просроченные партии и обновляет доступность блюд (вызывать по крону)
-- Отмечает просроченные партии и обновляет доступность
CREATE OR REPLACE FUNCTION fn_mark_expired_batches_and_update()
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    UPDATE ingredient_batches SET active = FALSE WHERE expiry_date IS NOT NULL AND expiry_date < now()::date AND active = TRUE;
    -- Обновить доступность для всех ресторанов
    PERFORM fn_update_dishes_availability_for_restaurant(r.id) FROM restaurants r;
END;
$$;

-- Простой механизм для предложения альтернатив: по той же категории и доступности
CREATE OR REPLACE FUNCTION fn_suggest_alternatives(p_dish_id INT, p_restaurant_id INT, p_limit INT DEFAULT 5)
RETURNS TABLE (dish_id INT, name TEXT, similarity_score FLOAT) LANGUAGE sql AS $$
    SELECT d.id, d.name, 1.0 AS similarity_score
    FROM dishes d
    WHERE d.restaurant_id = p_restaurant_id
      AND d.category = (SELECT category FROM dishes WHERE id = p_dish_id)
      AND d.is_available = TRUE
      AND d.id <> p_dish_id
    LIMIT p_limit;
$$;

-- триггер для пересчёта суммы заказа при изменении позиций
CREATE OR REPLACE FUNCTION trg_order_items_recalc_total()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    PERFORM fn_recalc_order_total(
        COALESCE(NEW.order_id, OLD.order_id)
    );
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_order_items_after_change
AFTER INSERT OR UPDATE OR DELETE ON order_items
FOR EACH ROW
EXECUTE FUNCTION trg_order_items_recalc_total();

-- ============= RLS политики =============
-- сощздаем роли
CREATE ROLE role_admin NOLOGIN;
CREATE ROLE role_analyst NOLOGIN;
CREATE ROLE role_manager NOLOGIN;
CREATE ROLE role_cook NOLOGIN;
CREATE ROLE role_waiter NOLOGIN;

-- 2. Create technical app user
CREATE ROLE app_user LOGIN PASSWORD 'strong_password';

-- 3. Grant roles to technical user
GRANT role_admin, role_analyst, role_manager, role_cook, role_waiter TO app_user;

-- 4. Grant privileges

-- Admin: полный доступ
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO role_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO role_admin;

-- Analyst: полный доступ на чтение
GRANT SELECT ON
cities, restaurants, restaurant_tables,
employees, employee_assignments,
dishes, dish_ingredients, dish_price_history,
orders, order_items,
ingredients, ingredient_batches, inventory_movements, purchase_requests,
suppliers, reservations, feedbacks, audit_logs
TO role_analyst;

-- Manager: заказы, инвентарь, сотрудники
GRANT SELECT, INSERT, UPDATE ON
orders, order_items, reservations, purchase_requests
TO role_manager;

GRANT SELECT, INSERT, UPDATE ON
ingredient_batches, inventory_movements
TO role_manager;

-- Cook: смотерть заказы и ингредиенты
GRANT SELECT ON
orders, order_items, dishes, dish_ingredients
TO role_cook;

GRANT SELECT ON
ingredients, ingredient_batches
TO role_cook;

GRANT INSERT ON purchase_requests TO role_cook;

-- Waiter: заказы и блюда
GRANT SELECT ON dishes TO role_waiter;
GRANT SELECT, INSERT ON orders, order_items TO role_waiter;
GRANT UPDATE (status) ON orders TO role_waiter;

--=========RLS: ПОЛИТИКИ ДЛЯ ВСЕХ КЛЮЧЕВЫХ ТАБЛИЦ
-- ====================== Orders ============================
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Admin и Analyst видят все
CREATE POLICY orders_admin_analyst_policy ON orders
FOR ALL
USING (
    current_setting('app.role', true) IN ('admin','analyst')
);

-- Manager: только свой ресторан
CREATE POLICY orders_manager_policy ON orders
FOR ALL
USING (
    current_setting('app.role', true) = 'manager'
    AND restaurant_id::text = current_setting('app.restaurant_id', true)
);

-- Waiter/Cook: только свой ресторан
CREATE POLICY orders_waiter_cook_policy ON orders
FOR SELECT
USING (
    current_setting('app.role', true) IN ('waiter','cook')
    AND restaurant_id::text = current_setting('app.restaurant_id', true)
);

-- ====================== Order_items =======================
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;

-- Admin и Analyst видят все
CREATE POLICY order_items_admin_analyst_policy ON order_items
FOR ALL
USING (
    current_setting('app.role', true) IN ('admin','analyst')
);

-- Manager: только свой ресторан через join с orders
CREATE POLICY order_items_manager_policy ON order_items
FOR ALL
USING (
    current_setting('app.role', true) = 'manager'
    AND order_id IN (SELECT id FROM orders WHERE restaurant_id::text = current_setting('app.restaurant_id', true))
);

-- Waiter/Cook: только свой ресторан
CREATE POLICY order_items_waiter_cook_policy ON order_items
FOR SELECT
USING (
    current_setting('app.role', true) IN ('waiter','cook')
    AND order_id IN (SELECT id FROM orders WHERE restaurant_id::text = current_setting('app.restaurant_id', true))
);

CREATE POLICY order_items_waiter_insert_policy ON order_items
FOR INSERT
WITH CHECK (
    current_setting('app.role', true) = 'waiter'
    AND order_id IN (
        SELECT id FROM orders
        WHERE restaurant_id::text = current_setting('app.restaurant_id', true)
    )
);

CREATE POLICY order_items_manager_insert_policy ON order_items
FOR INSERT
WITH CHECK (
    current_setting('app.role', true) = 'manager'
    AND order_id IN (
        SELECT id FROM orders
        WHERE restaurant_id::text = current_setting('app.restaurant_id', true)
    )
);

-- ====================== Ingredients & Batches =======================
ALTER TABLE ingredients ENABLE ROW LEVEL SECURITY;
ALTER TABLE ingredient_batches ENABLE ROW LEVEL SECURITY;

-- Admin и Analyst видят все
CREATE POLICY ingredients_admin_analyst_policy ON ingredients FOR ALL
USING (current_setting('app.role', true) IN ('admin','analyst'));
CREATE POLICY ingredient_batches_admin_analyst_policy ON ingredient_batches FOR ALL
USING (current_setting('app.role', true) IN ('admin','analyst'));

-- Manager & Cook: только свой ресторан
CREATE POLICY ingredient_batches_manager_cook_policy ON ingredient_batches FOR ALL
USING (
    current_setting('app.role', true) IN ('manager','cook')
    AND restaurant_id::text = current_setting('app.restaurant_id', true)
);

-- ====================== Dishes =======================
ALTER TABLE dishes ENABLE ROW LEVEL SECURITY;

-- Admin & Analyst: полный доступ
CREATE POLICY dishes_admin_analyst_policy ON dishes FOR ALL
USING (current_setting('app.role', true) IN ('admin','analyst'));

-- Manager/Cook/Waiter: свой ресторан
CREATE POLICY dishes_restaurant_policy ON dishes FOR SELECT
USING (
    current_setting('app.role', true) IN ('manager','cook','waiter')
    AND restaurant_id::text = current_setting('app.restaurant_id', true)
);

-- ====================== Purchase Requests =======================
ALTER TABLE purchase_requests ENABLE ROW LEVEL SECURITY;

-- Admin/Analyst: полный доступ
CREATE POLICY purchase_admin_analyst_policy ON purchase_requests FOR ALL
USING (current_setting('app.role', true) IN ('admin','analyst'));

-- Manager/Cook: только свой ресторан
CREATE POLICY purchase_manager_cook_policy ON purchase_requests FOR ALL
USING (
    current_setting('app.role', true) IN ('manager','cook')
    AND restaurant_id::text = current_setting('app.restaurant_id', true)
);

-- ====================== Inventory Movements =======================
ALTER TABLE inventory_movements ENABLE ROW LEVEL SECURITY;

-- Admin/Analyst: полный доступ
CREATE POLICY inv_admin_analyst_policy ON inventory_movements FOR ALL
USING (current_setting('app.role', true) IN ('admin','analyst'));

-- Manager/Cook: только свой ресторан
CREATE POLICY inv_manager_cook_policy ON inventory_movements FOR ALL
USING (
    current_setting('app.role', true) IN ('manager','cook')
    AND restaurant_id::text = current_setting('app.restaurant_id', true)
);

-- ====================== Reservations =======================
ALTER TABLE reservations ENABLE ROW LEVEL SECURITY;

-- Admin/Analyst: полный доступ
CREATE POLICY reservations_admin_analyst_policy ON reservations FOR ALL
USING (current_setting('app.role', true) IN ('admin','analyst'));

-- Manager/Waiter: только свой ресторан
CREATE POLICY reservations_manager_waiter_policy ON reservations FOR ALL
USING (
    current_setting('app.role', true) IN ('manager','waiter')
    AND restaurant_id::text = current_setting('app.restaurant_id', true)
);

-- ====================== Feedbacks =======================
ALTER TABLE feedbacks ENABLE ROW LEVEL SECURITY;

-- Admin/Analyst: полный доступ
CREATE POLICY feedbacks_admin_analyst_policy ON feedbacks FOR ALL
USING (current_setting('app.role', true) IN ('admin','analyst'));

-- Manager: только свой ресторан через join с orders
CREATE POLICY feedbacks_manager_policy ON feedbacks FOR ALL
USING (
    current_setting('app.role', true) = 'manager'
    AND order_id IN (SELECT id FROM orders WHERE restaurant_id::text = current_setting('app.restaurant_id', true))
);

-- ====================== Employees =======================
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;

-- Admin: полный доступ
CREATE POLICY employees_admin_policy ON employees FOR ALL
USING (current_setting('app.role', true) = 'admin');

-- Manager: только сотрудники своего ресторана
CREATE POLICY employees_manager_policy ON employees FOR SELECT
USING (
    current_setting('app.role', true) = 'manager'
    AND id IN (SELECT employee_id FROM employee_assignments WHERE restaurant_id::text = current_setting('app.restaurant_id', true))
);

-- Политика для waiter/cook: только своего ресторана, but only select/insert as needed
-- (для brevity policies can be extended similarly)

-- ============= ИНДЕКСЫ ДЛЯ АНАЛИТИКИ =============
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_dish_id ON order_items(dish_id);
CREATE INDEX idx_dishes_restaurant ON dishes(restaurant_id);
CREATE INDEX idx_batches_restaurant_ingredient ON ingredient_batches(restaurant_id, ingredient_id);
CREATE INDEX idx_inventory_movements_restaurant ON inventory_movements(restaurant_id, created_at);
CREATE INDEX idx_purchase_requests_restaurant ON purchase_requests(restaurant_id, status);
CREATE INDEX idx_dish_ingredients_dish ON dish_ingredients(dish_id);

-- GIN индексы уже созданы выше для search

-- =========================
-- ГОРОДА
-- =========================
INSERT INTO cities (name) VALUES
('Москва'),
('Санкт-Петербург'),
('Казань'),
('Новосибирск'),
('Екатеринбург');

-- =========================
-- РЕСТОРАНЫ
-- =========================
INSERT INTO restaurants (city_id, name, address, postal_code, phone, capacity, tables_count) VALUES
(1, 'Central Restaurant', 'Тверская, 1', '442963', '+7(967)-711-711', 125, 50),
(1, 'Pasta House', 'Арбат, 12', '442964', '+7(967)-711-712', 130, 52),
(2, 'Nord Cafe', 'Невский, 10', '442965', '+7(967)-711-713', 150, 60),
(3, 'Volga Food', 'Баумана, 5', '442966', '+7(967)-711-714', 180, 80),
(4, 'Siberia Grill', 'Ленина, 20', '442967', '+7(967)-711-715', 200, 100),
(5, 'Balzi Rossi', 'Красная пресня, 15', '442968', '+7(967)-711-716', 300, 125);


-- =========================
-- РОЛИ (бизнес)
-- =========================
INSERT INTO app_roles (name) VALUES
('admin'),
('manager'),
('cook'),
('waiter'),
('analyst')
ON CONFLICT DO NOTHING;

-- =========================
-- СОТРУДНИКИ
-- =========================
INSERT INTO employees (
    full_name, position, phone, email, experience_years, age, salary, hired_at
) VALUES
('Иван Админ', 'Администратор', '+7 900 000 00 10', 'admin@example.com', 10, 40, 120000, '2020-01-01'),
('Мария Менеджер', 'Менеджер', '+7 900 000 00 11', 'manager1@example.com', 6, 30, 80000, '2021-03-10'),
('Сергей Менеджер', 'Менеджер', '+7 900 000 00 12', 'manager2@example.com', 7, 40, 82000, '2021-04-15'),
('Олег Повар', 'Повар', '+7 900 000 00 13', 'cook1@example.com', 8, 25, 70000, '2020-06-20'),
('Алексей Повар', 'Повар', '+7 900 000 00 14', 'cook2@example.com', 5, 35, 65000, '2022-02-11'),
('Анна Официант', 'Официант', '+7 900 000 00 15', 'waiter1@example.com', 2, 28, 40000, '2023-01-05'),
('Екатерина Официант', 'Официант', '+7 900 000 00 16', 'waiter2@example.com', 3, 36, 42000, '2022-09-01');

INSERT INTO employee_assignments (employee_id, restaurant_id)
SELECT e.id, r.id
FROM employees e
JOIN restaurants r ON r.name = 'Central Restaurant'
WHERE e.full_name IN ('Мария Менеджер','Олег Повар','Анна Официант');

INSERT INTO employee_assignments (employee_id, restaurant_id)
SELECT e.id, r.id
FROM employees e
JOIN restaurants r ON r.name = 'Nord Cafe'
WHERE e.full_name IN ('Сергей Менеджер','Алексей Повар','Екатерина Официант');
-- =========================
-- ПОЛЬЗОВАТЕЛИ ПРИЛОЖЕНИЯ
-- =========================
INSERT INTO app_users (employee_id, username, password_hash)
SELECT id, 'admin', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u' FROM employees WHERE full_name = 'Иван Админ';

INSERT INTO app_users (employee_id, username, password_hash)
SELECT id, 'manager1', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u' FROM employees WHERE full_name = 'Мария Менеджер';

INSERT INTO app_users (employee_id, username, password_hash)
SELECT id, 'manager2', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u' FROM employees WHERE full_name = 'Сергей Менеджер';

INSERT INTO app_users (employee_id, username, password_hash)
SELECT id, 'cook1', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u' FROM employees WHERE full_name = 'Олег Повар';

INSERT INTO app_users (employee_id, username, password_hash)
SELECT id, 'cook2', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u' FROM employees WHERE full_name = 'Алексей Повар';

INSERT INTO app_users (employee_id, username, password_hash)
SELECT id, 'waiter1', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u' FROM employees WHERE full_name = 'Анна Официант';

INSERT INTO app_users (employee_id, username, password_hash)
SELECT id, 'waiter2', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u' FROM employees WHERE full_name = 'Екатерина Официант';

INSERT INTO app_user_roles (user_id, role_id, restaurant_id)
SELECT u.id, r.id, NULL
FROM app_users u
JOIN app_roles r ON r.name = 'admin'
WHERE u.username = 'admin';


-- Менеджеры
INSERT INTO app_user_roles (user_id, role_id, restaurant_id)
SELECT
    u.id,
    (SELECT id FROM app_roles WHERE name = 'manager'),
    (SELECT id FROM restaurants WHERE name = 'Central Restaurant')
FROM app_users u
WHERE u.username = 'manager1';

INSERT INTO app_user_roles (user_id, role_id, restaurant_id)
SELECT
    u.id,
    (SELECT id FROM app_roles WHERE name = 'manager'),
    (SELECT id FROM restaurants WHERE name = 'Nord Cafe')
FROM app_users u
WHERE u.username = 'manager2';

INSERT INTO app_user_roles (user_id, role_id, restaurant_id)
SELECT
    u.id,
    (SELECT id FROM app_roles WHERE name = 'cook'),
    (SELECT id FROM restaurants WHERE name = 'Central Restaurant')
FROM app_users u
WHERE u.username = 'cook1';

INSERT INTO app_user_roles (user_id, role_id, restaurant_id)
SELECT
    u.id,
    (SELECT id FROM app_roles WHERE name = 'cook'),
    (SELECT id FROM restaurants WHERE name = 'Nord Cafe')
FROM app_users u
WHERE u.username = 'cook2';

-- Официанты
INSERT INTO app_user_roles (user_id, role_id, restaurant_id)
SELECT
    u.id,
    (SELECT id FROM app_roles WHERE name = 'waiter'),
    (SELECT id FROM restaurants WHERE name = 'Central Restaurant')
FROM app_users u
WHERE u.username = 'waiter1';

INSERT INTO app_user_roles (user_id, role_id, restaurant_id)
SELECT
    u.id,
    (SELECT id FROM app_roles WHERE name = 'waiter'),
    (SELECT id FROM restaurants WHERE name = 'Nord Cafe')
FROM app_users u
WHERE u.username = 'waiter2';


-- =========================
-- БЛЮДА
-- =========================
INSERT INTO dishes (restaurant_id, name, category, price, prep_time_minutes) VALUES
(1, 'Паста Карбонара', 'Паста', 650, 20),
(1, 'Цезарь с курицей', 'Салаты', 700, 15),
(1, 'Тирамису', 'Десерты', 400, 10),
(1, 'Борщ', 'Супы', 375, 25),
(1, 'Паста Феттучини', 'Паста', 750, 20),

(2, 'Пицца Маргарита', 'Пицца', 800, 30),
(2, 'Пицца Пепперони', 'Пицца', 1000, 30),
(2, 'Паста Карбонара', 'Паста', 660, 20),
(2, 'Цезарь с курицей', 'Салаты', 700, 15),
(2, 'Капрезе', 'Салаты', 600, 15),

(3, 'Суп Том Ям', 'Супы', 700, 25),
(3, 'Жареный лосось', 'Горячее', 900, 20),
(3, 'Жареный рис с курицей', 'Горячее', 600, 25),
(3, 'Томатный суп с курицей', 'Супы', 650, 20),
(3, 'Овощной салат', 'Салат', 500, 10),

(4, 'Томленная говядина', 'Горячее', 2000, 35),
(4, 'Тар-тар из говядины', 'Деликатесы', 1500, 10),
(4, 'Жареный лосось', 'Горячее', 1500, 20),
(4, 'Стейк', 'Горячее', 1650, 15),
(4, 'Русский салат', 'Салат', 600, 10),

(5, 'Рис с говядиной', 'Горячее', 1400, 25),
(5, 'Тар-тар из говядины', 'Деликатесы', 1500, 10),
(5, 'Тар-тар из лосося', 'Деликатесы', 1500, 10),
(5, 'Тирамису', 'Десерт', 500, 5),
(5, 'Русский салат', 'Салат', 600, 10),

(6, 'Пицца Мортаделла', 'Пицца', 1350, 25),
(6, 'Жареный рис с курицей', 'Горячее', 650, 25),
(6, 'Жареный лосось', 'Горячее', 1500, 20),
(6, 'Овощной салат', 'Салат', 700, 10),
(6, 'Греческий салат', 'Салат', 750, 10);

-- =========================
-- ИНГРЕДИЕНТЫ
-- =========================
INSERT INTO ingredients (name, unit) VALUES
('Спагетти', 'г'),
('Бекон', 'г'),
('Яйцо', 'шт'),
('Пармезан', 'г'),
('Курица', 'г'),
('Салат Романо', 'г'),
('Мука', 'г'),
('Томаты', 'г'),
('Сыр Моцарелла', 'г'),
('Пепперони', 'г'), -- 10
('Овощи', 'г'), -- 11
('Говядина', 'г'),
('Лосось', 'г'),
('Мортаделла', 'г'),
('Рис', 'г'), -- 15
('Тирамису', 'г'),
('Огурец', 'г'),
('Маслины', 'г'),
('Лук', 'г'),
('Сливки', 'г'), -- 20
('Базилик', 'г');


-- =========================
-- СОСТАВ БЛЮД
-- =========================
INSERT INTO dish_ingredients (dish_id, ingredient_id, qty_required) VALUES

-- 1 Паста Карбонара
(1, 1, 120),
(1, 2, 50),
(1, 3, 1),
(1, 4, 20),

-- 2 Цезарь с курицей
(2, 5, 120),
(2, 6, 80),
(2, 4, 20),

-- 3 Тирамису
(3, 16, 2),

-- 4 Борщ
(4, 12, 150),
(4, 11, 200),

-- 5 Паста Феттучини
(5, 1, 120),
(5, 4, 30),

-- 6 Пицца Маргарита
(6, 7, 200),
(6, 8, 150),
(6, 9, 120),

-- 7 Пицца Пепперони
(7, 7, 200),
(7, 8, 150),
(7, 9, 120),
(7, 10, 80),

-- 8 Паста Карбонара
(8, 1, 120),
(8, 2, 50),
(8, 3, 1),
(8, 4, 20),

-- 9 Цезарь с курицей
(9, 5, 120),
(9, 6, 80),
(9, 4, 20),

-- 10 Капрезе
(10, 8, 120),
(10, 9, 150),
(10, 21, 10),

-- 11 Суп Том Ям
(11, 5, 150),
(11, 11, 100),

-- 12 Жареный лосось
(12, 13, 250),

-- 13 Жареный рис с курицей
(13, 15, 180),
(13, 5, 120),

-- 14 Томатный суп с курицей
(14, 8, 200),
(14, 5, 120),

-- 15 Овощной салат
(15, 11, 200),

-- 16 Томленная говядина
(16, 12, 300),

-- 17 Тар-тар из говядины
(17, 12, 200),

-- 18 Жареный лосось
(18, 13, 250),

-- 19 Стейк
(19, 12, 350),

-- 20 Русский салат
(20, 11, 200),
(20, 19, 80),

-- 21 Рис с говядиной
(21, 15, 180),
(21, 12, 150),

-- 22 Тар-тар из говядины
(22, 12, 200),

-- 23 Тар-тар из лосося
(23, 13, 200),

-- 24 Тирамису
(24, 16, 2),
-- 25 Русский салат
(25, 8, 200),
(25, 19, 80),

-- 26 Пицца Мортаделла
(26, 7, 200),
(26, 8, 150),
(26, 9, 120),
(26, 14, 100),

-- 27 Жареный рис с курицей
(27, 15, 180),
(27, 5, 120),

-- 28 Жареный лосось
(28, 13, 250),

-- 29 Овощной салат
(29, 11, 200),

-- 30 Греческий салат
(30, 8, 120),
(30, 9, 150);


INSERT INTO dish_ingredients (dish_id, ingredient_id, qty_required)
SELECT 8, id, 100
FROM ingredients
WHERE name = 'Фуа-гра';

-- =========================
-- ПАРТИИ ИНГРЕДИЕНТОВ (FIFO)
-- =========================
-- Central Restaurant (id=1): Паста, Салаты, Десерты
INSERT INTO ingredient_batches (ingredient_id, restaurant_id, batch_no, min_threshold, qty, expiry_date) VALUES
(1, 1, 'SPAGETTI-CENTRAL', 5, 5000, now() + interval '15 days'),  -- Спагетти
(2, 1, 'BACON-CENTRAL', 5, 1000, now() + interval '10 days'),  -- Бекон
(3, 1, 'EGGS-CENTRAL', 5, 2000,  now() + interval '14 days'),  -- Яйцо
(4, 1, 'PARMEZAN-CENTRAL', 5, 1500, now() + interval '30 days'),  -- Пармезан
(5, 1, 'CHICKEN-CENTRAL', 5, 3000, now() + interval '6 days'),   -- Курица
(6, 1, 'SALAD-CENTRAL', 5, 2000, now() + interval '10 days'),  -- Салат
(11, 1, 'VEG-CENTRAL', 5, 3000, now() + interval '6 days'),   -- овощи
(12, 1, 'MEET-CENTRAL', 5, 3000, now() + interval '6 days'),   -- мясо
(16, 1, 'TIRAMISY-CENTRAL', 5, 1000, now() + interval '2 days'),
(20,1, 'SLIVKI-CENTRAL', 10, 1500, now() + interval '15 days');


-- Pasta House (id=2): Пиццы
INSERT INTO ingredient_batches (ingredient_id, restaurant_id, batch_no, min_threshold, qty, expiry_date) VALUES
(1, 2, 'SPAGETTI-PASTA', 5, 500000, now() + interval '15 days'),  -- Спагетти
(2, 2, 'BACON-PASTA', 5, 100000, now() + interval '10 days'),  -- Бекон
(3, 2, 'EGGS-PASTA', 5, 200000,  now() + interval '14 days'),  -- Яйцо
(4, 2, 'PARMEZAN-PASTA', 5, 150000, now() + interval '30 days'),  -- Пармезан
(5, 2, 'CHICKEN-PASTA', 5, 300000, now() + interval '6 days'),   -- Курица
(6, 2, 'SALAD-PASTA', 5, 200000, now() + interval '10 days'),  -- Салат
(7, 2, 'FLOUR-PASTA', 200, 300000, now() + interval '20 days'),  -- Мука
(8, 2, 'TOMATO-PASTA', 150, 200000, now() + interval '10 days'), -- Томаты
(9, 2, 'MOZARELLA-PASTA', 100, 150000, now() + interval '15 days'), -- Моцарелла
(10, 2, 'PEPPERONI-PASTA', 100, 150000, now() + interval '15 days'); -- Пепперони


-- Nord Cafe (id=3): Супы, Гарниры, Горячее
INSERT INTO ingredient_batches (ingredient_id, restaurant_id, batch_no, min_threshold, qty, expiry_date) VALUES
(5, 3, 'CHICKEN-NORD', 5, 300000, now() + interval '6 days'),   -- Курица
(6, 3, 'SALAD-NORD', 5, 200000, now() + interval '10 days'),  -- Салат
(8, 3, 'TOMATO-NORD', 150, 200000, now() + interval '10 days'), -- Томаты
(11, 3, 'VEG-NORD', 100, 150000, now() + interval '15 days'), -- ОВОЩИ
(13, 3, 'SALMON-NORD', 100, 150000, now() + interval '15 days'), -- Лосось
(15, 3, 'RICE-NORD', 100, 150000, now() + interval '15 days'),
(17, 3, 'CUCUMBER-NORD', 100, 150000, now() + interval '15 days');

-- Volga Food (id=4): Русская кухня
INSERT INTO ingredient_batches (ingredient_id, restaurant_id, batch_no, min_threshold, qty, expiry_date) VALUES
(8, 4, 'TOMATO-VOLGA', 150, 200000, now() + interval '10 days'), -- Томаты
(11, 4, 'VEG-NORD', 100, 150000, now() + interval '15 days'), -- ОВОЩИ
(12, 4, 'MEET-VOLGA', 100, 150000, now() + interval '15 days'), -- Говядина
(13, 4, 'SALMON-VOLGA', 100, 150000, now() + interval '15 days'), -- Лосось
(19, 4, 'ONOION-VOLGA', 100, 150000, now() + interval '15 days'); -- ЛУК

-- Siberia Grill (id=5): Премиум-блюда
INSERT INTO ingredient_batches (ingredient_id, restaurant_id, batch_no, min_threshold, qty, expiry_date) VALUES
(8, 5, 'TOMATO-SIB', 150, 200000, now() + interval '10 days'), -- Томаты
(12, 5, 'MEET-SIB', 100, 150000, now() + interval '15 days'), -- Говядина
(13, 5, 'SALMON-SIB', 100, 150000, now() + interval '15 days'), -- Лосось
(15, 5, 'RICE-SIB', 100, 150000, now() + interval '15 days'),
(16, 5, 'TIRAMISY-SIB', 100, 150000, now() + interval '15 days'),
(19, 5, 'ONION-SIB', 100, 150000, now() + interval '15 days');

-- Balzi Rossi (id=6): Итальянская пицца
INSERT INTO ingredient_batches (ingredient_id, restaurant_id, batch_no, min_threshold, qty, expiry_date) VALUES
(5, 6, 'CHICKEN-BALZI', 5, 300000, now() + interval '6 days'),   -- Курица
(6, 6, 'SALAD-BALZI', 5, 200000, now() + interval '10 days'),  -- Салат
(7, 6, 'FLOUR-BALZI', 200, 300000, now() + interval '20 days'),  -- Мука
(8, 6, 'TOMATO-BALZI', 150, 200000, now() + interval '10 days'), -- Томаты
(9, 6, 'MOZARELLA-BALZI', 100, 150000, now() + interval '15 days'), -- Моцарелла
(11, 6, 'VEG-BALZI', 100, 150000, now() + interval '15 days'), -- Овощи
(13, 6, 'SALMON-BALZI', 100, 150000, now() + interval '15 days'), -- Лосось
(14, 6, 'MORTA-BALZI', 50, 500000, now() + interval '12 days'), -- Мортаделла
(15, 6, 'RICE-BALZI', 100, 150000, now() + interval '15 days'),
(17, 6, 'CUCUMBER-BALZI', 100, 150000, now() + interval '15 days'),
(18, 6, 'MASLIN-BALZI', 100, 150000, now() + interval '15 days');


-- =========================
-- ЗАКАЗЫ и столы
-- =========================
-- Столы для Central Restaurant (id=1)
-- Столы: по 5 на каждый ресторан
DO $$
BEGIN
    FOR r IN 1..6 LOOP
        FOR t IN 1..5 LOOP
            INSERT INTO restaurant_tables (restaurant_id, table_number, seats)
            VALUES (r, t::TEXT, CASE WHEN t <= 3 THEN 4 ELSE 6 END);
        END LOOP;
    END LOOP;
END $$;

-- Central Restaurant (id=1)
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user) VALUES
(1, 1, 'Иван Петров', 'created', (SELECT id FROM app_users WHERE username = 'waiter1'));
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(1, 1, 2, 650),  -- Паста Карбонара
(1, 2, 1, 700);  -- Цезарь с курицей

-- Pasta House (id=2)
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user) VALUES
(2, 2, 'Алексей Кузнецов', 'created', (SELECT id FROM app_users WHERE username = 'waiter2'));
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(2, 7, 1, 1000),  -- Пицца Пепперони
(2, 6, 1, 800);   -- Пицца Маргарита

-- Nord Cafe (id=3)
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user) VALUES
(3, 1, 'Елена Волкова', 'created', (SELECT id FROM app_users WHERE username = 'waiter2'));
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(3, 11, 1, 700),  -- Суп Том Ям
(3, 12, 2, 600);  -- Жареный рис с курицей

-- Volga Food (id=4)
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user) VALUES
(4, 2, 'Дмитрий Смирнов', 'created', (SELECT id FROM app_users WHERE username = 'waiter1'));
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(4, 16, 1, 2000),  -- Томленная говядина
(4, 20, 1, 600);  -- Русский салат

-- Siberia Grill (id=5)
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user) VALUES
(5, 1, 'Ольга Новикова', 'created', (SELECT id FROM app_users WHERE username = 'waiter1'));
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(5, 21, 1, 1400), -- Рис с говядиной
(5, 23, 1, 1500); -- Тар-тар из лосося

-- Balzi Rossi (id=6)
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user) VALUES
(6, 2, 'Сергей Иванов', 'created', (SELECT id FROM app_users WHERE username = 'waiter2'));
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(6, 26, 2, 1350); -- Пицца Мортаделла

-- =========================
-- ДОПОЛНИТЕЛЬНЫЕ ЗАКАЗЫ (по 2 на ресторан)
-- =========================
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(1, 2, 'Анна Сидорова', 'created', (SELECT id FROM app_users WHERE username = 'waiter1'), '2025-12-18 09:15:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(7, 1, 1, 650),  -- Паста Карбонара
(7, 3, 1, 400);  -- Тирамису

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(1, 1, 'Михаил Петров', 'created', (SELECT id FROM app_users WHERE username = 'waiter1'), '2025-12-18 22:45:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(8, 2, 2, 700);  -- Цезарь с курицей

-- Pasta House (id=2) — заказы 9, 10
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(2, 1, 'Ольга Иванова', 'created', (SELECT id FROM app_users WHERE username = 'waiter2'), '2025-12-18 13:20:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(9, 7, 2, 1000), -- Пицца Пепперони
(9, 8, 1, 660);  -- Паста Карбонара

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(2, 3, 'Дмитрий Кузнецов', 'created', (SELECT id FROM app_users WHERE username = 'waiter2'), '2025-12-18 20:30:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(10, 9, 1, 700), -- Цезарь с курицей
(10, 7, 1, 1000);

-- Nord Cafe (id=3) — заказы 11, 12
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(3, 2, 'Екатерина Смирнова', 'created', (SELECT id FROM app_users WHERE username = 'waiter2'), '2025-12-18 11:00:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(11, 11, 1, 700); -- Суп Том Ям

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(3, 4, 'Артём Волков', 'created', (SELECT id FROM app_users WHERE username = 'waiter2'), '2025-12-18 19:20:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(12, 13, 2, 600); -- Жареный рис с курицей

-- Volga Food (id=4) — заказы 13, 14
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(4, 1, 'Сергей Новиков', 'created', (SELECT id FROM app_users WHERE username = 'waiter1'), '2025-12-18 12:10:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(13, 19, 1, 1650); -- Стейк

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(4, 3, 'Наталья Попова', 'created', (SELECT id FROM app_users WHERE username = 'waiter1'), '2025-12-18 21:00:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(14, 16, 2, 2000); -- Томленная говядина

-- Siberia Grill (id=5) — заказы 15, 16
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(5, 2, 'Илья Морозов', 'created', (SELECT id FROM app_users WHERE username = 'waiter1'), '2025-12-18 14:50:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(15, 22, 1, 1500); -- Тар-тар из говядины

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(5, 4, 'Виктория Зайцева', 'created', (SELECT id FROM app_users WHERE username = 'waiter1'), '2025-12-18 22:00:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(16, 23, 1, 1500), -- Тар-тар из лосося
(16, 25, 1, 600); -- Русский салат

-- Balzi Rossi (id=6) — заказы 17, 18
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(6, 1, 'Роман Кузнецов', 'created', (SELECT id FROM app_users WHERE username = 'waiter2'), '2025-12-18 10:30:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(17, 26, 1, 1350); -- Пицца Мортаделла

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(6, 3, 'Людмила Орлова', 'created', (SELECT id FROM app_users WHERE username = 'waiter2'), '2025-12-18 18:45:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(18, 30, 1, 750), -- Греческий салат
(18, 28, 2, 1500); -- Жареный лосось


UPDATE orders SET order_time = '2025-12-19 12:30:00' WHERE id = 1;  -- Central Restaurant (днём)
UPDATE orders SET order_time = '2025-12-19 20:15:00' WHERE id = 2;  -- Pasta House (вечер)
UPDATE orders SET order_time = '2025-12-19 19:45:00' WHERE id = 3;  -- Nord Cafe (вечер)
UPDATE orders SET order_time = '2025-12-19 14:20:00' WHERE id = 4;  -- Volga Food (днём)
UPDATE orders SET order_time = '2025-12-19 21:30:00' WHERE id = 5;  -- Siberia Grill (после 21:00)
UPDATE orders SET order_time = '2025-12-19 18:00:00' WHERE id = 6;

-- =========================
-- ФИНАЛИЗАЦИЯ ЧАСТИ ЗАКАЗОВ
-- =========================
SELECT fn_finalize_order(1);
SELECT fn_finalize_order(2);
SELECT fn_finalize_order(3);
SELECT fn_finalize_order(4);
SELECT fn_finalize_order(5);
SELECT fn_finalize_order(6);
SELECT fn_finalize_order(7);
SELECT fn_finalize_order(8);
SELECT fn_finalize_order(9);
SELECT fn_finalize_order(10);
SELECT fn_finalize_order(11);
SELECT fn_finalize_order(12);
SELECT fn_finalize_order(13);
SELECT fn_finalize_order(14);
SELECT fn_finalize_order(15);
SELECT fn_finalize_order(16);
SELECT fn_finalize_order(17);
SELECT fn_finalize_order(18);