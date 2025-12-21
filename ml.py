import os
import pandas as pd
import matplotlib.pyplot as plt
from sqlalchemy import create_engine
from sklearn.cluster import KMeans
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

DB_CONFIG = {
    "dbname": "restaurant_management",
    "user": "restaurant_admin",
    "password": "secure_password_123",
    "host": "localhost",
    "port": 5432
}

DATABASE_URL = f"postgresql://{DB_CONFIG['user']}:{DB_CONFIG['password']}@{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['dbname']}"

os.makedirs("ml_results", exist_ok=True)

print("Загружаем данные...")
engine = create_engine(DATABASE_URL)

sql = """
SELECT 
    d.name AS dish_name,
    SUM(oi.qty) AS total_qty,
    SUM(oi.qty * oi.price_at_order) AS total_revenue,
    d.price
FROM dishes d
LEFT JOIN order_items oi ON oi.dish_id = d.id
LEFT JOIN orders o ON o.id = oi.order_id AND o.status IN ('completed', 'served')
GROUP BY d.id, d.name, d.price
HAVING SUM(oi.qty) > 0
ORDER BY total_revenue DESC;
      """

df = pd.read_sql(sql, engine)
engine.dispose()

print(f"Блюд с продажами: {len(df)}")

if len(df) >= 3:
    print("\nКластеризация на 3 группы...")

    # Признаки
    X = df[['total_revenue', 'total_qty']].values


    pipeline = Pipeline([
        ('scaler', StandardScaler()),
        ('kmeans', KMeans(n_clusters=3, random_state=42)),
    ])

    df['cluster'] = pipeline.fit_predict(X)

    cluster_info = {}
    for cluster_id in range(3):
        cluster_data = df[df['cluster'] == cluster_id]
        avg_revenue = cluster_data['total_revenue'].mean()
        avg_qty = cluster_data['total_qty'].mean()

        if avg_revenue > df['total_revenue'].mean() and avg_qty > df['total_qty'].mean():
            name = "ХИТЫ"
        elif avg_revenue < df['total_revenue'].mean() and avg_qty < df['total_qty'].mean():
            name = "СЛАБЫЕ"
        else:
            name = "СРЕДНИЕ"

        cluster_info[cluster_id] = name
        df.loc[df['cluster'] == cluster_id, 'cluster_name'] = name

    # 3. Создаём график
    plt.figure(figsize=(12, 8))

    # Цвета для кластеров
    colors = ['green', 'orange', 'red']

    for i, (cluster_id, name) in enumerate(cluster_info.items()):
        cluster_data = df[df['cluster'] == cluster_id]

        plt.scatter(
            cluster_data['total_qty'],
            cluster_data['total_revenue'],
            s=100,
            c=colors[i],
            alpha=0.7,
            edgecolors='black',
            linewidth=1,
            label=f'{name} ({len(cluster_data)} блюд)'
        )

        # Добавляем названия блюд для топ-3 в каждом кластере
        top_dishes = cluster_data.nlargest(3, 'total_revenue')
        for _, row in top_dishes.iterrows():
            plt.annotate(
                row['dish_name'][:15],  # Ограничиваем длину названия
                xy=(row['total_qty'], row['total_revenue']),
                xytext=(5, 5),
                textcoords='offset points',
                fontsize=9,
                alpha=0.8
            )

    # Настройки графика
    plt.xlabel('Количество продаж (шт)', fontsize=12)
    plt.ylabel('Выручка (руб)', fontsize=12)
    plt.title('Кластеризация блюд по продажам', fontsize=14, fontweight='bold')
    plt.grid(True, alpha=0.3)
    plt.legend(fontsize=11)

    # Добавляем общую статистику
    stats_text = f"""
    Всего блюд: {len(df)}
    Общая выручка: {df['total_revenue'].sum():,.0f} руб
    Общее количество: {df['total_qty'].sum():,.0f} шт
    """
    plt.figtext(0.15, 0.02, stats_text, fontsize=10,
                bbox=dict(boxstyle="round,pad=0.5", facecolor="lightgray", alpha=0.8))

    # Сохраняем график
    plt.tight_layout()
    plt.savefig('ml_results/clusters_plot.png', dpi=150, bbox_inches='tight')
    print("График сохранён: ml_results/clusters_plot.png")