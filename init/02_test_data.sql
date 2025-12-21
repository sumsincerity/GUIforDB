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
('Администратор Системы', 'Админ', '+7-963 100 12 12','admin@example.com', 10, 30, 300000, '2020-01-01'),
('Андрей Менеджер', 'Менеджер', '+7 900 000 01 01', 'manager_r1@example.com', 6, 38, 85000, '2021-02-01'),
('Павел Повар', 'Повар', '+7 900 000 01 02', 'cook_r1@example.com', 7, 34, 70000, '2020-05-12'),
('Ирина Официант', 'Официант', '+7 900 000 01 03', 'waiter_r1_1@example.com', 3, 25, 42000, '2023-01-15'),
('Ольга Официант', 'Официант', '+7 900 000 01 04', 'waiter_r1_2@example.com', 2, 23, 40000, '2023-06-01'),

('Виктор Менеджер', 'Менеджер', '+7 900 000 02 01', 'manager_r2@example.com', 8, 41, 88000, '2020-09-10'),
('Артем Повар', 'Повар', '+7 900 000 02 02', 'cook_r2@example.com', 6, 29, 68000, '2021-11-20'),
('Марина Официант', 'Официант', '+7 900 000 02 03', 'waiter_r2_1@example.com', 4, 27, 43000, '2022-04-18'),
('Никита Официант', 'Официант', '+7 900 000 02 04', 'waiter_r2_2@example.com', 1, 22, 39000, '2024-02-10'),

('Станислав Менеджер', 'Менеджер', '+7 900 000 03 01', 'manager_r3@example.com', 5, 36, 82000, '2022-01-05'),
('Денис Повар', 'Повар', '+7 900 000 03 02', 'cook_r3@example.com', 9, 45, 75000, '2019-08-14'),
('Елена Официант', 'Официант', '+7 900 000 03 03', 'waiter_r3_1@example.com', 3, 26, 41000, '2023-03-01'),
('Юлия Официант', 'Официант', '+7 900 000 03 04', 'waiter_r3_2@example.com', 2, 24, 40000, '2023-09-10'),

('Роман Менеджер', 'Менеджер', '+7 900 000 04 01', 'manager_r4@example.com', 7, 39, 87000, '2020-12-12'),
('Максим Повар', 'Повар', '+7 900 000 04 02', 'cook_r4@example.com', 10, 44, 78000, '2018-04-03'),
('Антон Официант', 'Официант', '+7 900 000 04 03', 'waiter_r4_1@example.com', 4, 30, 44000, '2022-06-06'),
('Дарья Официант', 'Официант', '+7 900 000 04 04', 'waiter_r4_2@example.com', 3, 28, 42000, '2022-11-15'),

('Кирилл Менеджер', 'Менеджер', '+7 900 000 05 01', 'manager_r5@example.com', 9, 42, 90000, '2019-07-07'),
('Игорь Повар', 'Повар', '+7 900 000 05 02', 'cook_r5@example.com', 8, 37, 74000, '2020-10-01'),
('Полина Официант', 'Официант', '+7 900 000 05 03', 'waiter_r5_1@example.com', 2, 23, 40000, '2023-05-20'),
('Валерия Официант', 'Официант', '+7 900 000 05 04', 'waiter_r5_2@example.com', 3, 26, 42000, '2022-08-18'),

('Александр Менеджер', 'Менеджер', '+7 900 000 06 01', 'manager_r6@example.com', 6, 35, 83000, '2021-03-30'),
('Евгений Повар', 'Повар', '+7 900 000 06 02', 'cook_r6@example.com', 7, 33, 71000, '2021-09-09'),
('Ксения Официант', 'Официант', '+7 900 000 06 03', 'waiter_r6_1@example.com', 2, 22, 39000, '2024-01-12'),
('Алина Официант', 'Официант', '+7 900 000 06 04', 'waiter_r6_2@example.com', 3, 25, 41000, '2023-04-04');

INSERT INTO employee_assignments (employee_id, restaurant_id)
SELECT e.id, r.id
FROM employees e
JOIN restaurants r ON r.name = 'Central Restaurant'
WHERE e.full_name IN (
    'Андрей Менеджер',
    'Павел Повар',
    'Ирина Официант',
    'Ольга Официант'
);

INSERT INTO employee_assignments (employee_id, restaurant_id)
SELECT e.id, r.id
FROM employees e
JOIN restaurants r ON r.name = 'Pasta House'
WHERE e.full_name IN (
    'Виктор Менеджер',
    'Артем Повар',
    'Марина Официант',
    'Никита Официант'
);

INSERT INTO employee_assignments (employee_id, restaurant_id)
SELECT e.id, r.id
FROM employees e
JOIN restaurants r ON r.name = 'Nord Cafe'
WHERE e.full_name IN (
    'Станислав Менеджер',
    'Денис Повар',
    'Елена Официант',
    'Юлия Официант'
);

INSERT INTO employee_assignments (employee_id, restaurant_id)
SELECT e.id, r.id
FROM employees e
JOIN restaurants r ON r.name = 'Volga Food'
WHERE e.full_name IN (
    'Роман Менеджер',
    'Максим Повар',
    'Антон Официант',
    'Дарья Официант'
);

INSERT INTO employee_assignments (employee_id, restaurant_id)
SELECT e.id, r.id
FROM employees e
JOIN restaurants r ON r.name = 'Siberia Grill'
WHERE e.full_name IN (
    'Кирилл Менеджер',
    'Игорь Повар',
    'Полина Официант',
    'Валерия Официант'
);

INSERT INTO employee_assignments (employee_id, restaurant_id)
SELECT e.id, r.id
FROM employees e
JOIN restaurants r ON r.name = 'Balzi Rossi'
WHERE e.full_name IN (
    'Александр Менеджер',
    'Евгений Повар',
    'Ксения Официант',
    'Алина Официант'
);

-- =========================
-- ПОЛЬЗОВАТЕЛИ ПРИЛОЖЕНИЯ
-- =========================

INSERT INTO app_users (employee_id, username, password_hash)
SELECT
    (SELECT id FROM employees WHERE email = 'admin@example.com'),
    'admin',
    '$2b$12$8UWu08SEa7byZNCr.3uVx.W64.M4xbcaioHLs/GfRj9tXbTMTtbAe'  -- hash для пароля "password"
ON CONFLICT (username) DO NOTHING;

-- Менеджеры
INSERT INTO app_users (employee_id, username, password_hash) VALUES
((SELECT id FROM employees WHERE full_name = 'Андрей Менеджер'), 'manager1', '$2b$12$aVEUyQMJMSgSpBYY/MDha.hPFr/PanIsffYcPsLMKCsmE2Oq05x62'),
((SELECT id FROM employees WHERE full_name = 'Виктор Менеджер'), 'manager2', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
((SELECT id FROM employees WHERE full_name = 'Станислав Менеджер'), 'manager3', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
((SELECT id FROM employees WHERE full_name = 'Роман Менеджер'), 'manager4', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
((SELECT id FROM employees WHERE full_name = 'Кирилл Менеджер'), 'manager5', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
((SELECT id FROM employees WHERE full_name = 'Александр Менеджер'), 'manager6', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u');

-- Повара
INSERT INTO app_users (employee_id, username, password_hash) VALUES
((SELECT id FROM employees WHERE full_name = 'Павел Повар'), 'cook1', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
((SELECT id FROM employees WHERE full_name = 'Артем Повар'), 'cook2', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
((SELECT id FROM employees WHERE full_name = 'Денис Повар'), 'cook3', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
((SELECT id FROM employees WHERE full_name = 'Максим Повар'), 'cook4', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
((SELECT id FROM employees WHERE full_name = 'Игорь Повар'), 'cook5', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
((SELECT id FROM employees WHERE full_name = 'Евгений Повар'), 'cook6', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u');

-- Официанты
INSERT INTO app_users (employee_id, username, password_hash) VALUES
-- Central
((SELECT id FROM employees WHERE full_name = 'Ирина Официант'), 'waiter1', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
((SELECT id FROM employees WHERE full_name = 'Ольга Официант'), 'waiter2', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
-- Pasta House
((SELECT id FROM employees WHERE full_name = 'Марина Официант'), 'waiter3', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
((SELECT id FROM employees WHERE full_name = 'Никита Официант'), 'waiter4', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
-- Nord Cafe
((SELECT id FROM employees WHERE full_name = 'Елена Официант'), 'waiter5', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
((SELECT id FROM employees WHERE full_name = 'Юлия Официант'), 'waiter6', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
-- Volga Food
((SELECT id FROM employees WHERE full_name = 'Антон Официант'), 'waiter7', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
((SELECT id FROM employees WHERE full_name = 'Дарья Официант'), 'waiter8', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
-- Siberia Grill
((SELECT id FROM employees WHERE full_name = 'Полина Официант'), 'waiter9', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
((SELECT id FROM employees WHERE full_name = 'Валерия Официант'), 'waiter10', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
-- Balzi Rossi
((SELECT id FROM employees WHERE full_name = 'Ксения Официант'), 'waiter11', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u'),
((SELECT id FROM employees WHERE full_name = 'Алина Официант'), 'waiter12', '$2b$12$4Tm2Z3Y6sQqW9X7a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0u');


INSERT INTO app_user_roles (user_id, role_id, restaurant_id)
SELECT u.id, r.id, NULL
FROM app_users u
JOIN app_roles r ON r.name = 'admin'
WHERE u.username = 'admin';

INSERT INTO app_user_roles (user_id, role_id, restaurant_id)
SELECT
    u.id,
    (SELECT id FROM app_roles WHERE name = 'manager'),
    e.restaurant_id
FROM app_users u
JOIN employees emp ON u.employee_id = emp.id
JOIN employee_assignments e ON emp.id = e.employee_id
WHERE u.username LIKE 'manager%';

-- Повара
INSERT INTO app_user_roles (user_id, role_id, restaurant_id)
SELECT
    u.id,
    (SELECT id FROM app_roles WHERE name = 'cook'),
    e.restaurant_id
FROM app_users u
JOIN employees emp ON u.employee_id = emp.id
JOIN employee_assignments e ON emp.id = e.employee_id
WHERE u.username LIKE 'cook%';

-- Официанты
INSERT INTO app_user_roles (user_id, role_id, restaurant_id)
SELECT
    u.id,
    (SELECT id FROM app_roles WHERE name = 'waiter'),
    e.restaurant_id
FROM app_users u
JOIN employees emp ON u.employee_id = emp.id
JOIN employee_assignments e ON emp.id = e.employee_id
WHERE u.username LIKE 'waiter%';

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
(1, 2, 'SPAGETTI-PASTA', 5, 5000, now() + interval '15 days'),  -- Спагетти
(2, 2, 'BACON-PASTA', 5, 1000, now() + interval '10 days'),  -- Бекон
(3, 2, 'EGGS-PASTA', 5, 2000,  now() + interval '14 days'),  -- Яйцо
(4, 2, 'PARMEZAN-PASTA', 5, 1500, now() + interval '30 days'),  -- Пармезан
(5, 2, 'CHICKEN-PASTA', 5, 3000, now() + interval '6 days'),   -- Курица
(6, 2, 'SALAD-PASTA', 5, 2000, now() + interval '10 days'),  -- Салат
(7, 2, 'FLOUR-PASTA', 200, 3000, now() + interval '20 days'),  -- Мука
(8, 2, 'TOMATO-PASTA', 150, 2000, now() + interval '10 days'), -- Томаты
(9, 2, 'MOZARELLA-PASTA', 100, 1500, now() + interval '15 days'), -- Моцарелла
(10, 2, 'PEPPERONI-PASTA', 100, 1500, now() + interval '15 days'); -- Пепперони


-- Nord Cafe (id=3): Супы, Гарниры, Горячее
INSERT INTO ingredient_batches (ingredient_id, restaurant_id, batch_no, min_threshold, qty, expiry_date) VALUES
(5, 3, 'CHICKEN-NORD', 5, 3000, now() + interval '6 days'),   -- Курица
(6, 3, 'SALAD-NORD', 5, 2000, now() + interval '10 days'),  -- Салат
(8, 3, 'TOMATO-NORD', 150, 2000, now() + interval '10 days'), -- Томаты
(11, 3, 'VEG-NORD', 100, 1500, now() + interval '15 days'), -- ОВОЩИ
(13, 3, 'SALMON-NORD', 100, 1500, now() + interval '15 days'), -- Лосось
(15, 3, 'RICE-NORD', 100, 1500, now() + interval '15 days'),
(17, 3, 'CUCUMBER-NORD', 100, 1500, now() + interval '15 days');

-- Volga Food (id=4): Русская кухня
INSERT INTO ingredient_batches (ingredient_id, restaurant_id, batch_no, min_threshold, qty, expiry_date) VALUES
(8, 4, 'TOMATO-VOLGA', 150, 2000, now() + interval '10 days'), -- Томаты
(11, 4, 'VEG-NORD', 100, 1500, now() + interval '15 days'), -- ОВОЩИ
(12, 4, 'MEET-VOLGA', 100, 1500, now() + interval '15 days'), -- Говядина
(13, 4, 'SALMON-VOLGA', 100, 1500, now() + interval '15 days'), -- Лосось
(19, 4, 'ONOION-VOLGA', 100, 1500, now() + interval '15 days'); -- ЛУК

-- Siberia Grill (id=5): Премиум-блюда
INSERT INTO ingredient_batches (ingredient_id, restaurant_id, batch_no, min_threshold, qty, expiry_date) VALUES
(8, 5, 'TOMATO-SIB', 150, 2000, now() + interval '10 days'), -- Томаты
(12, 5, 'MEET-SIB', 100, 1500, now() + interval '15 days'), -- Говядина
(13, 5, 'SALMON-SIB', 100, 1500, now() + interval '15 days'), -- Лосось
(15, 5, 'RICE-SIB', 100, 1500, now() + interval '15 days'),
(16, 5, 'TIRAMISY-SIB', 100, 1500, now() + interval '15 days'),
(19, 5, 'ONION-SIB', 100, 1500, now() + interval '15 days');

-- Balzi Rossi (id=6): Итальянская пицца
INSERT INTO ingredient_batches (ingredient_id, restaurant_id, batch_no, min_threshold, qty, expiry_date) VALUES
(5, 6, 'CHICKEN-BALZI', 5, 3000, now() + interval '6 days'),   -- Курица
(6, 6, 'SALAD-BALZI', 5, 2000, now() + interval '10 days'),  -- Салат
(7, 6, 'FLOUR-BALZI', 200, 3000, now() + interval '20 days'),  -- Мука
(8, 6, 'TOMATO-BALZI', 150, 2000, now() + interval '10 days'), -- Томаты
(9, 6, 'MOZARELLA-BALZI', 100, 1500, now() + interval '15 days'), -- Моцарелла
(11, 6, 'VEG-BALZI', 100, 1500, now() + interval '15 days'), -- Овощи
(13, 6, 'SALMON-BALZI', 100, 1500, now() + interval '15 days'), -- Лосось
(14, 6, 'MORTA-BALZI', 50, 5000, now() + interval '12 days'), -- Мортаделла
(15, 6, 'RICE-BALZI', 100, 1500, now() + interval '15 days'),
(17, 6, 'CUCUMBER-BALZI', 100, 1500, now() + interval '15 days'),
(18, 6, 'MASLIN-BALZI', 100, 1500, now() + interval '15 days');


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
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(1, 1, 'Иван Петров', 'created', (SELECT id FROM app_users WHERE username = 'waiter1'), '2025-12-21 09:35:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(1, 1, 2, 650),  -- Паста Карбонара
(1, 2, 1, 700);  -- Цезарь с курицей

-- Pasta House (id=2)
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(2, 2, 'Алексей Кузнецов', 'created', (SELECT id FROM app_users WHERE username = 'waiter3'), '2025-12-20 10:37:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(2, 7, 1, 1000),  -- Пицца Пепперони
(2, 6, 1, 800);   -- Пицца Маргарита

-- Nord Cafe (id=3)
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(3, 1, 'Елена Волкова', 'created', (SELECT id FROM app_users WHERE username = 'waiter5'), '2025-12-21 17:45:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(3, 11, 1, 700),  -- Суп Том Ям
(3, 12, 2, 600);  -- Жареный рис с курицей

-- Volga Food (id=4)
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(4, 2, 'Дмитрий Смирнов', 'created', (SELECT id FROM app_users WHERE username = 'waiter7'), '2025-12-19 14:45:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(4, 16, 1, 2000),  -- Томленная говядина
(4, 20, 1, 600);  -- Русский салат

-- Siberia Grill (id=5)
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(5, 1, 'Ольга Новикова', 'created', (SELECT id FROM app_users WHERE username = 'waiter9'), '2025-12-20 19:15:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(5, 21, 1, 1400), -- Рис с говядиной
(5, 23, 1, 1500); -- Тар-тар из лосося

-- Balzi Rossi (id=6)
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(6, 2, 'Сергей Иванов', 'created', (SELECT id FROM app_users WHERE username = 'waiter11'), '2025-12-21 17:44:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(6, 26, 2, 1350); -- Пицца Мортаделла

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(1, 2, 'Анна Сидорова', 'created', (SELECT id FROM app_users WHERE username = 'waiter1'), '2025-12-18 09:15:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(7, 1, 1, 650),  -- Паста Карбонара
(7, 3, 1, 400);  -- Тирамису

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(1, 1, 'Михаил Петров', 'created', (SELECT id FROM app_users WHERE username = 'waiter2'), '2025-12-18 22:45:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(8, 2, 2, 700);  -- Цезарь с курицей

-- Pasta House (id=2) — заказы 9, 10
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(2, 1, 'Ольга Иванова', 'created', (SELECT id FROM app_users WHERE username = 'waiter3'), '2025-12-18 13:20:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(9, 7, 2, 1000), -- Пицца Пепперони
(9, 8, 1, 660);  -- Паста Карбонара

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(2, 3, 'Дмитрий Кузнецов', 'created', (SELECT id FROM app_users WHERE username = 'waiter4'), '2025-12-18 20:30:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(10, 9, 1, 700), -- Цезарь с курицей
(10, 7, 1, 1000);

-- Nord Cafe (id=3) — заказы 11, 12
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(3, 2, 'Екатерина Смирнова', 'created', (SELECT id FROM app_users WHERE username = 'waiter5'), '2025-12-18 11:00:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(11, 11, 1, 700); -- Суп Том Ям

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(3, 4, 'Артём Волков', 'created', (SELECT id FROM app_users WHERE username = 'waiter6'), '2025-12-18 19:20:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(12, 13, 2, 600); -- Жареный рис с курицей

-- Volga Food (id=4) — заказы 13, 14
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(4, 1, 'Сергей Новиков', 'created', (SELECT id FROM app_users WHERE username = 'waiter7'), '2025-12-18 12:10:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(13, 19, 1, 1650); -- Стейк

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(4, 3, 'Наталья Попова', 'created', (SELECT id FROM app_users WHERE username = 'waiter8'), '2025-12-18 21:00:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(14, 16, 2, 2000); -- Томленная говядина

-- Siberia Grill (id=5) — заказы 15, 16
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(5, 2, 'Илья Морозов', 'created', (SELECT id FROM app_users WHERE username = 'waiter9'), '2025-12-18 14:50:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(15, 22, 1, 1500); -- Тар-тар из говядины

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(5, 4, 'Виктория Зайцева', 'created', (SELECT id FROM app_users WHERE username = 'waiter10'), '2025-12-18 22:00:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(16, 23, 1, 1500), -- Тар-тар из лосося
(16, 25, 1, 600); -- Русский салат

-- Balzi Rossi (id=6) — заказы 17, 18
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(6, 1, 'Роман Кузнецов', 'created', (SELECT id FROM app_users WHERE username = 'waiter11'), '2025-12-18 10:30:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(17, 26, 1, 1350); -- Пицца Мортаделла

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(6, 3, 'Людмила Орлова', 'created', (SELECT id FROM app_users WHERE username = 'waiter12'), '2025-12-18 18:45:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(18, 30, 1, 750), -- Греческий салат
(18, 28, 2, 1500); -- Жареный лосось

-- Central Restaurant (id=1) — заказы 19, 20
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(1, 3, 'Екатерина Лебедева', 'created', (SELECT id FROM app_users WHERE username = 'waiter1'), '2025-12-18 13:10:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(19, 5, 1, 750),  -- Паста Феттучини
(19, 4, 1, 375);  -- Борщ

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(1, 4, 'Артём Белов', 'created', (SELECT id FROM app_users WHERE username = 'waiter2'), '2025-12-18 20:40:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(20, 3, 2, 400),  -- Тирамису
(20, 1, 1, 650);  -- Паста Карбонара

-- Pasta House (id=2) — заказы 21, 22
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(2, 4, 'Дарья Соколова', 'created', (SELECT id FROM app_users WHERE username = 'waiter3'), '2025-12-18 12:25:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(21, 6, 1, 800);  -- Пицца Маргарита

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(2, 5, 'Игорь Фёдоров', 'created', (SELECT id FROM app_users WHERE username = 'waiter4'), '2025-12-18 19:50:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(22, 8, 1, 660),  -- Паста Карбонара
(22, 7, 2, 1000); -- Пицца Пепперони

-- Nord Cafe (id=3) — заказы 23, 24
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(3, 3, 'Полина Морозова', 'created', (SELECT id FROM app_users WHERE username = 'waiter5'), '2025-12-18 14:15:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(23, 15, 1, 500), -- Овощной салат
(23, 14, 1, 650); -- Томатный суп с курицей

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(3, 5, 'Роман Зайцев', 'created', (SELECT id FROM app_users WHERE username = 'waiter6'), '2025-12-18 21:20:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(24, 12, 1, 900), -- Жареный лосось
(24, 13, 1, 600); -- Жареный рис с курицей

-- Volga Food (id=4) — заказы 25, 26
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(4, 4, 'Анна Волкова', 'created', (SELECT id FROM app_users WHERE username = 'waiter7'), '2025-12-18 13:40:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(25, 18, 1, 1500), -- Жареный лосось
(25, 20, 1, 600);  -- Русский салат

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(4, 5, 'Максим Семёнов', 'created', (SELECT id FROM app_users WHERE username = 'waiter8'), '2025-12-18 20:10:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(26, 17, 1, 1500), -- Тар-тар из говядины
(26, 19, 1, 1650); -- Стейк

-- Siberia Grill (id=5) — заказы 27, 28
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(5, 3, 'Алина Кузнецова', 'created', (SELECT id FROM app_users WHERE username = 'waiter9'), '2025-12-18 15:30:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(27, 24, 2, 500), -- Тирамису
(27, 25, 1, 600); -- Русский салат

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(5, 5, 'Станислав Петров', 'created', (SELECT id FROM app_users WHERE username = 'waiter10'), '2025-12-18 22:15:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(28, 21, 1, 1400), -- Рис с говядиной
(28, 22, 1, 1500); -- Тар-тар из говядины

-- Balzi Rossi (id=6) — заказы 29, 30
INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(6, 4, 'Юлия Новикова', 'created', (SELECT id FROM app_users WHERE username = 'waiter11'), '2025-12-18 12:50:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(29, 29, 1, 700), -- Овощной салат
(29, 27, 2, 650); -- Жареный рис с курицей

INSERT INTO orders (restaurant_id, table_id, guest_name, status, created_by_user, order_time) VALUES
(6, 5, 'Дмитрий Орлов', 'created', (SELECT id FROM app_users WHERE username = 'waiter12'), '2025-12-18 19:00:00');
INSERT INTO order_items (order_id, dish_id, qty, price_at_order) VALUES
(30, 28, 1, 1500), -- Жареный лосось
(30, 30, 1, 750);  -- Греческий салат
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
SELECT fn_finalize_order(14);
SELECT fn_finalize_order(15);
SELECT fn_finalize_order(16);
SELECT fn_finalize_order(17);
SELECT fn_finalize_order(18);
SELECT fn_finalize_order(19);
SELECT fn_finalize_order(21);
SELECT fn_finalize_order(22);
SELECT fn_finalize_order(23);
SELECT fn_finalize_order(24);
SELECT fn_finalize_order(25);
SELECT fn_finalize_order(26);
SELECT fn_finalize_order(27);
SELECT fn_finalize_order(28);
SELECT fn_finalize_order(29);
SELECT fn_finalize_order(30);