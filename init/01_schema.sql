-- Подключаем расширения
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; --генерация uuid
CREATE EXTENSION IF NOT EXISTS pg_trgm; -- для полнотекстового поиска
CREATE EXTENSION IF NOT EXISTS btree_gin; -- позволяет использовать GIN-индексы с обычными операторами

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
    max_concurrent_orders INT DEFAULT 10,
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
        RAISE EXCEPTION 'Работник % уже зарегистрирован в ресторане другого города', NEW.employee_id;
    END IF;
    RETURN NEW;
END;
$$;

-- триггер на сотрудника в одном городе
CREATE TRIGGER trg_employee_assignments_city
BEFORE INSERT OR UPDATE ON employee_assignments
FOR EACH ROW EXECUTE FUNCTION fn_check_employee_assignments_city();

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

CREATE TABLE app_user_roles (
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    role_id INT NOT NULL REFERENCES app_roles(id) ON DELETE CASCADE,
    restaurant_id INT REFERENCES restaurants(id),
    PRIMARY KEY (user_id, role_id)
);

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
    unit TEXT,
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

-- Движение на складе
CREATE TABLE inventory_movements (
    id SERIAL PRIMARY KEY,
    batch_id INT REFERENCES ingredient_batches(id),
    ingredient_id INT REFERENCES ingredients(id),
    restaurant_id INT REFERENCES restaurants(id),
    change_qty NUMERIC(12,4) NOT NULL,
    reason TEXT,
    related_order_id INT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- Запросы на покупку  (статусы доступные нам new, ordered, received, cancelled)
CREATE TABLE purchase_requests (
    id SERIAL PRIMARY KEY,
    restaurant_id INT REFERENCES restaurants(id),
    ingredient_id INT REFERENCES ingredients(id),
    qty NUMERIC(12,4) NOT NULL,
    status TEXT NOT NULL DEFAULT 'new',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

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
    qty_required NUMERIC(12,4) NOT NULL,
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

-- заказы с привязкой к ресторану, столу, гостю, времени и статусу
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    restaurant_id INT NOT NULL REFERENCES restaurants(id),
    table_id INT REFERENCES restaurant_tables(id),
    guest_name TEXT,
    created_by_user UUID REFERENCES app_users(id),
    completed_by_user UUID REFERENCES app_users(id),
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

CREATE OR REPLACE FUNCTION fn_get_eta_for_restaurant(p_restaurant_id INT)
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
    v_current INT;
    v_max INT;
    v_avg_prep_time INT;
BEGIN
    SELECT COUNT(*) INTO v_current
    FROM orders
    WHERE restaurant_id = p_restaurant_id
      AND status IN ('created', 'confirmed', 'preparing');

    SELECT max_concurrent_orders INTO v_max FROM restaurants WHERE id = p_restaurant_id;
    SELECT COALESCE(AVG(prep_time_minutes), 20) INTO v_avg_prep_time
    FROM dishes WHERE restaurant_id = p_restaurant_id;

    IF v_current < v_max THEN
        RETURN NULL; -- можно сейчас
    ELSE
        -- ETA = (текущие заказы - лимит + 1) * среднее время готовки
        RETURN (v_current - v_max + 1) * v_avg_prep_time;
    END IF;
END;
$$;

-- Возвращает рестораны в том же городе с доступным ETA
CREATE OR REPLACE FUNCTION fn_suggest_alternative_restaurants(p_restaurant_id INT)
RETURNS TABLE (id INT, name TEXT, eta_minutes INT) LANGUAGE sql AS $$
    WITH current_city AS (
        SELECT city_id FROM restaurants WHERE id = p_restaurant_id
    )
    SELECT r.id, r.name, fn_get_eta_for_restaurant(r.id) AS eta_minutes
    FROM restaurants r, current_city c
    WHERE r.city_id = c.city_id
      AND r.id <> p_restaurant_id
      AND (fn_get_eta_for_restaurant(r.id) IS NULL OR fn_get_eta_for_restaurant(r.id) < 60)
    ORDER BY eta_minutes NULLS FIRST
    LIMIT 3;
$$;

-- Обновляет completed_by_user при финализации заказа
CREATE OR REPLACE FUNCTION fn_set_completed_by_user()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.status = 'completed' AND OLD.status <> 'completed' THEN
        NEW.completed_by_user = current_setting('app.user_id', true)::UUID;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_orders_set_completed_by_user
BEFORE UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION fn_set_completed_by_user();

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

CREATE INDEX idx_orders_restaurant_time ON orders (restaurant_id, order_time);

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

-- статусы booked, cancelled, no_show, completed
CREATE TABLE reservations (
    id SERIAL PRIMARY KEY,
    restaurant_id INT NOT NULL REFERENCES restaurants(id),
    table_id INT REFERENCES restaurant_tables(id),
    guest_name TEXT,
    reserved_from TIMESTAMP WITH TIME ZONE NOT NULL,
    reserved_to TIMESTAMP WITH TIME ZONE NOT NULL,
    status TEXT DEFAULT 'booked'
);

-- Вспомогательная: суммарный остаток ингредиента в ресторане (по активным партиям)
CREATE OR REPLACE FUNCTION fn_total_ingredient_qty(p_ingredient_id INT, p_restaurant_id INT)
RETURNS NUMERIC LANGUAGE sql AS $$
    SELECT COALESCE(SUM(qty),0) FROM ingredient_batches
    WHERE ingredient_id = p_ingredient_id AND restaurant_id = p_restaurant_id AND active = TRUE;
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
CREATE OR REPLACE FUNCTION fn_finalize_order(p_order_id INT, p_user_id UUID DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM orders WHERE id = p_order_id AND is_finalized = TRUE) THEN
        RAISE EXCEPTION 'Order % already finalized', p_order_id;
    END IF;

    PERFORM fn_decrease_stock_for_order(p_order_id);

    UPDATE orders
    SET is_finalized = TRUE,
        status = 'completed',
        completed_at = now(),
        completed_by_user = COALESCE(p_user_id, created_by_user)  -- ← ИЗМЕНЕНО
    WHERE id = p_order_id;
END;
$$;

-- Функция, которая помечает просроченные партии и обновляет доступность блюд
-- Отмечает просроченные партии и обновляет доступность
CREATE OR REPLACE FUNCTION fn_mark_expired_batches_and_update()
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    UPDATE ingredient_batches SET active = FALSE WHERE expiry_date IS NOT NULL AND expiry_date < now()::date AND active = TRUE;
    -- Обновить доступность для всех ресторанов
    PERFORM fn_update_dishes_availability_for_restaurant(r.id) FROM restaurants r;
END;
$$;

-- механизм для предложения альтернатив: по той же категории и доступности
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

-- orders
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

-- order_items
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

-- ingridients, batches
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

-- dishes
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

-- purchase request
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

-- inventory movement
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

-- reservations
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

-- feedbacks
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

-- employees
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

-- индексы для аналитики
CREATE INDEX idx_order_items_order_id ON order_items(order_id);
CREATE INDEX idx_order_items_dish_id ON order_items(dish_id);
CREATE INDEX idx_dishes_restaurant ON dishes(restaurant_id);
CREATE INDEX idx_batches_restaurant_ingredient ON ingredient_batches(restaurant_id, ingredient_id);
CREATE INDEX idx_inventory_movements_restaurant ON inventory_movements(restaurant_id, created_at);
CREATE INDEX idx_purchase_requests_restaurant ON purchase_requests(restaurant_id, status);
CREATE INDEX idx_dish_ingredients_dish ON dish_ingredients(dish_id);