import os
import pandas as pd
import psycopg2
import matplotlib.pyplot as plt
import warnings
warnings.filterwarnings('ignore')

# ================== CONFIG ==================
DB_CONFIG = {
    "dbname": "restaurant_management",
    "user": "restaurant_admin",
    "password": "secure_password_123",
    "host": "localhost",
    "port": 5432
}

# Создаём папку visualizations, если её нет
os.makedirs("visualizations", exist_ok=True)

# ================== CONNECTION ==================
conn = psycopg2.connect(**DB_CONFIG)

# ================== 1. Популярные блюда ==================
sql_popular_dishes = """
SELECT
    r.name AS restaurant,
    d.name AS dish,
    SUM(oi.qty) AS total_qty
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
JOIN dishes d ON d.id = oi.dish_id
JOIN restaurants r ON r.id = o.restaurant_id
GROUP BY r.name, d.name
ORDER BY r.name, total_qty DESC;
"""

df = pd.read_sql(sql_popular_dishes, conn)

for restaurant in df['restaurant'].unique():
    subset = df[df['restaurant'] == restaurant].head(5)
    plt.figure(figsize=(10, 6))
    plt.bar(subset['dish'], subset['total_qty'])
    plt.title(f"Топ-5 блюд — {restaurant}")
    plt.xticks(rotation=45, ha='right')
    plt.tight_layout()
    plt.savefig(f"visualizations/top_dishes_{restaurant}.png")
    plt.close()  # Закрываем фигуру

# ================== 2. Загруженность по часам ==================
sql_hours = """
SELECT
    r.name AS restaurant,
    EXTRACT(HOUR FROM o.order_time) AS hour,
    COUNT(*) AS orders_count
FROM orders o
JOIN restaurants r ON r.id = o.restaurant_id
GROUP BY r.name, hour
ORDER BY r.name, hour;
"""

df_hours = pd.read_sql(sql_hours, conn)

for restaurant in df_hours['restaurant'].unique():
    sub = df_hours[df_hours['restaurant'] == restaurant]
    plt.figure(figsize=(10, 6))
    plt.plot(sub['hour'], sub['orders_count'], marker='o')
    plt.title(f"Загруженность — {restaurant}")
    plt.xlabel("Час")
    plt.ylabel("Заказы")
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(f"visualizations/hourly_load_{restaurant}.png")
    plt.close()

# ================== 3. Прибыль по категориям ==================
sql_category = """
SELECT
    r.name AS restaurant,
    d.category,
    SUM(oi.qty * oi.price_at_order) AS revenue
FROM order_items oi
JOIN orders o ON o.id = oi.order_id
JOIN dishes d ON d.id = oi.dish_id
JOIN restaurants r ON r.id = o.restaurant_id
GROUP BY r.name, d.category
ORDER BY revenue DESC;
"""

df_cat = pd.read_sql(sql_category, conn)

for restaurant in df_cat['restaurant'].unique():
    sub = df_cat[df_cat['restaurant'] == restaurant]
    plt.figure(figsize=(10, 6))
    plt.bar(sub['category'], sub['revenue'])
    plt.title(f"Прибыль по категориям — {restaurant}")
    plt.xticks(rotation=45, ha='right')
    plt.tight_layout()
    plt.savefig(f"visualizations/category_revenue_{restaurant}.png")
    plt.close()

# ================== 4. Топ ингредиентов ==================
sql_ing = """
SELECT
    i.name,
    SUM(di.qty_required * oi.qty) AS total_used
FROM order_items oi
JOIN dishes d ON d.id = oi.dish_id
JOIN dish_ingredients di ON di.dish_id = d.id
JOIN ingredients i ON i.id = di.ingredient_id
GROUP BY i.name
ORDER BY total_used DESC
LIMIT 10;
"""

df_ing = pd.read_sql(sql_ing, conn)

plt.figure(figsize=(12, 6))
plt.bar(df_ing['name'], df_ing['total_used'])
plt.title("Топ-10 используемых ингредиентов")
plt.xticks(rotation=45, ha='right')
plt.tight_layout()
plt.savefig("visualizations/top_ingredients.png")
plt.close()

# Закрываем соединение
conn.close()

print("✅ Все графики сохранены в папку 'visualizations'")