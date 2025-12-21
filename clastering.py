import os
import pandas as pd
from sqlalchemy import create_engine
from prophet import Prophet
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler
import matplotlib.pyplot as plt

DB_CONFIG = {
    "dbname": "restaurant_management",
    "user": "restaurant_admin",
    "password": "secure_password_123",
    "host": "localhost",
    "port": 5432
}

# Создаём папку для результатов
os.makedirs("ml_results", exist_ok=True)

DATABASE_URL = (
    f"postgresql://{DB_CONFIG['user']}:{DB_CONFIG['password']}"
    f"@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['dbname']}"
)

engine = create_engine(DATABASE_URL)

sql_demand = """
SELECT
    date_trunc('day', o.order_time AT TIME ZONE 'UTC')::DATE AS day,
    d.name AS dish,
    SUM(oi.qty) AS qty
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
JOIN dishes d ON d.id = oi.dish_id
WHERE o.status IN ('completed', 'served')
GROUP BY day, d.name
ORDER BY day;
"""

df = pd.read_sql(sql_demand, engine)

print("Всего строк для ML:", len(df))

if df.empty:
    print("Нет данных для прогноза спроса")
else:
    # Выбираем блюдо с максимальными продажами
    dish = df.groupby('dish')['qty'].sum().idxmax()
    ts = df[df['dish'] == dish][['day', 'qty']].copy()
    ts.columns = ['ds', 'y']
    ts = ts.sort_values('ds').reset_index(drop=True)

    if len(ts) < 2:
        print(f"Недостаточно данных для Prophet по блюду '{dish}'")
    else:
        model = Prophet()
        model.fit(ts)

        future = model.make_future_dataframe(periods=7, freq='D')
        forecast = model.predict(future)

        # Сохраняем график
        fig = model.plot(forecast)
        plt.title(f"Прогноз спроса: {dish}")
        plt.tight_layout()
        plt.savefig(f"ml_results/prophet_{dish}.png")
        plt.close()

        # Выводим прогноз
        print(f"\nПрогноз спроса на '{dish}' на следующие 7 дней:")
        print(forecast[['ds', 'yhat']].tail(7).to_string(index=False))

sql_cluster = """
SELECT
    d.name,
    d.category,
    AVG(oi.price_at_order) AS avg_price,
    SUM(oi.qty) AS total_qty,
    SUM(oi.qty * oi.price_at_order) AS revenue
FROM dishes d
JOIN order_items oi ON oi.dish_id = d.id
JOIN orders o ON oi.order_id = o.id
WHERE o.status IN ('completed', 'served')
GROUP BY d.name, d.category  -- ← ИСПРАВЛЕНО: добавлен d.category
HAVING SUM(oi.qty) > 0;
"""

dfc = pd.read_sql(sql_cluster, engine)
dfc = pd.get_dummies(dfc, columns=['category'])  # One-Hot Encoding
X = dfc.select_dtypes(include=['number']).drop(columns=['avg_price', 'total_qty', 'revenue'], errors='ignore')

if len(dfc) < 3:
    print("Недостаточно данных для кластеризации")
else:
    X = dfc[['avg_price', 'total_qty', 'revenue']]
    X_scaled = StandardScaler().fit_transform(X)

    kmeans = KMeans(n_clusters=3, random_state=42)
    dfc['cluster'] = kmeans.fit_predict(X_scaled)

    print("КЛАСТЕРЫ БЛЮД:")
    for _, row in dfc.iterrows():
        print(f"{row['name']}: кластер {row['cluster']}")

    # Сохраняем график
    plt.figure(figsize=(10, 6))
    scatter = plt.scatter(dfc['total_qty'], dfc['revenue'], c=dfc['cluster'], cmap='viridis')
    plt.xlabel("Общее количество продаж")
    plt.ylabel("Выручка")
    plt.title("Кластеризация блюд")
    plt.colorbar(scatter)
    plt.tight_layout()
    plt.savefig("ml_results/clusters.png")
    plt.close()

engine.dispose()  # Закрываем пул соединений
print("Все результаты сохранены в папку 'ml_results'")