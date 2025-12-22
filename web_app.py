import os
import bcrypt
import psycopg2
from psycopg2.extras import RealDictCursor
from flask import Flask, render_template, request, redirect, url_for, session, flash, Response
from dotenv import load_dotenv
from datetime import datetime
import gspread
from google.oauth2.service_account import Credentials

load_dotenv()

app = Flask(__name__)
app.secret_key = os.environ.get("SECRET_KEY", "dev_secret_change_me")

ROLE_PERMISSIONS = {
    "admin": {"admin", "tables", "query", "inventory", "orders", "menu", "reports", "purchase"},
    "analyst": {"tables", "query", "menu", "reports"},
    "manager": {"tables", "inventory", "orders", "menu", "reports", "purchase"},
    "cook": {"inventory", "orders", "menu", "purchase"},
    "waiter": {"orders", "menu"},
}


def format_datetime_columns(rows):
    if not rows:
        return rows
    formatted = []
    for row in rows:
        new_row = {}
        for key, value in row.items():
            if isinstance(value, datetime):
                new_row[key] = value.strftime('%Y-%m-%d %H:%M:%S')
            else:
                new_row[key] = value
        formatted.append(new_row)
    return formatted

def get_db_conn():
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "localhost"),
        port=os.environ.get("DB_PORT", "5432"),
        dbname=os.environ.get("DB_NAME", "restaurant_management"),
        user=os.environ.get("DB_USER", "restaurant_admin"),
        password=os.environ.get("DB_PASSWORD", "secure_password_123"),
    )


def list_tables():
    with get_db_conn() as conn, conn.cursor() as cur:
        cur.execute(
            """
            SELECT table_name
            FROM information_schema.tables
            WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
            ORDER BY table_name
            """
        )
        return [r[0] for r in cur.fetchall()]


def list_columns(table: str):
    with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(
            """
            SELECT
                column_name,
                data_type,
                is_nullable,
                column_default,
                is_identity
            FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = %s
            ORDER BY ordinal_position
            """,
            (table,),
        )
        rows = cur.fetchall()
        for row in rows:
            default = row.get("column_default") or ""
            row["is_serial"] = default.startswith("nextval(") or row.get("is_identity") == "YES"
        return format_datetime_columns(rows)


def list_restaurants() -> list[dict]:
    with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute("SELECT id, name FROM restaurants ORDER BY id")
        rows = cur.fetchall()
        return format_datetime_columns(rows)


def list_roles_public() -> list[str]:
    with get_db_conn() as conn, conn.cursor() as cur:
        cur.execute("SELECT name FROM app_roles WHERE name <> 'admin' ORDER BY name")
        return [r[0] for r in cur.fetchall()]


def get_counts() -> dict:
    counts = {"orders": 0, "stocks": 0, "dishes": 0}
    try:
        with get_db_conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) FROM orders")
            counts["orders"] = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM ingredient_batches")
            counts["stocks"] = cur.fetchone()[0]
            cur.execute("SELECT COUNT(*) FROM dishes")
            counts["dishes"] = cur.fetchone()[0]
    except Exception:
        pass
    return counts


def get_summary(role: str | None, rest_id: int | None) -> list[dict]:
    base_sql = """
        SELECT
          r.id AS restaurant_id,
          r.name AS restaurant_name,
          COUNT(DISTINCT o.id) AS orders_count,
          COALESCE(SUM(o.total_amount), 0) AS orders_sum,
          COUNT(DISTINCT s.id) AS stocks_count,
          COALESCE(SUM(s.qty), 0) AS stocks_qty
        FROM restaurants r
        LEFT JOIN orders o ON o.restaurant_id = r.id
        LEFT JOIN ingredient_batches s ON s.restaurant_id = r.id
    """
    clauses = []
    params: list = []
    if role != "admin":
        if rest_id:
            clauses.append("r.id = %s")
            params.append(rest_id)
    where_sql = (" WHERE " + " AND ".join(clauses)) if clauses else ""
    sql = f"""
        {base_sql}
        {where_sql}
        GROUP BY r.id, r.name
        ORDER BY r.id
    """
    with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
        return format_datetime_columns(rows)


def get_status_counts(role: str | None, rest_id: int | None) -> list[dict]:
    clauses = []
    params: list = []
    if role != "admin" and rest_id:
        clauses.append("o.restaurant_id = %s")
        params.append(rest_id)
    where_sql = "WHERE " + " AND ".join(clauses) if clauses else ""
    sql = f"""
        SELECT o.status, COUNT(*) AS cnt
        FROM orders o
        {where_sql}
        GROUP BY o.status
        ORDER BY o.status
    """
    with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql, params)
        return cur.fetchall()


def list_stocks(restaurant_id: int | None = None) -> list[dict]:
    clauses = []
    params: list = []
    if restaurant_id:
        clauses.append("s.restaurant_id = %s")
        params.append(restaurant_id)
    where_sql = "WHERE " + " AND ".join(clauses) if clauses else ""
    sql = f"""
        SELECT s.id, s.restaurant_id, s.ingredient_id, i.name AS ingredient_name,
               s.qty, s.unit, s.expiry_date, s.min_threshold, s.batch_no
        FROM ingredient_batches s
        JOIN ingredients i ON i.id = s.ingredient_id
        {where_sql}
        ORDER BY s.restaurant_id, i.name;
    """
    with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()

    # Форматируем expiry_date в 'YYYY-MM-DD'
    result = []
    for row in rows:
        new_row = {}
        for key, value in row.items():
            if key == 'expiry_date' and value is not None:
                new_row[key] = value.strftime('%Y-%m-%d')
            elif isinstance(value, datetime):
                new_row[key] = value.strftime('%Y-%m-%d %H:%M:%S')
            else:
                new_row[key] = value
        result.append(new_row)
    return result


def list_orders(restaurant_id: int | None, status: str | None) -> list[dict]:
    clauses = []
    params: list = []
    if restaurant_id:
        clauses.append("o.restaurant_id = %s")
        params.append(restaurant_id)
    if status:
        clauses.append("o.status = %s")
        params.append(status)
    where_sql = "WHERE " + " AND ".join(clauses) if clauses else ""
    sql = f"""
        SELECT
            o.id,
            o.restaurant_id,
            t.table_number,
            o.guest_name,
            o.status,
            o.order_time AS created_at,
            o.scheduled_for,
            o.total_amount
        FROM orders o
        LEFT JOIN restaurant_tables t ON t.id = o.table_id
        {where_sql}
        ORDER BY o.order_time DESC
        LIMIT 300;
    """
    with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
        return format_datetime_columns(rows)


def list_dishes_filtered(
    restaurant_id: int | None,
    category: str | None,
    is_available: bool | None,
    price_min: float | None,
    price_max: float | None,
    keyword: str | None,
) -> list[dict]:
    clauses = []
    params: list = []
    if restaurant_id:
        clauses.append("restaurant_id = %s")
        params.append(restaurant_id)
    if category:
        clauses.append("LOWER(category) = LOWER(%s)")
        params.append(category)
    if is_available is not None:
        clauses.append("is_available = %s")
        params.append(is_available)
    if price_min is not None:
        clauses.append("price >= %s")
        params.append(price_min)
    if price_max is not None:
        clauses.append("price <= %s")
        params.append(price_max)
    if keyword:
        clauses.append("searchable @@ plainto_tsquery('russian', %s)")
        params.append(keyword)
    where_sql = "WHERE " + " AND ".join(clauses) if clauses else ""
    sql = f"""
        SELECT id, restaurant_id, name, category, price, prep_time_minutes, is_available
        FROM dishes
        {where_sql}
        ORDER BY restaurant_id, name
        LIMIT 200;
    """
    with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
        return format_datetime_columns(rows)


def run_report_default():
    sql = """
        SELECT restaurant_id, COUNT(*) AS orders_count, SUM(total_amount) AS total_amount
        FROM orders
        GROUP BY restaurant_id
        ORDER BY restaurant_id;
    """
    with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql)
        rows = cur.fetchall()
        cols = list(rows[0].keys()) if rows else [desc.name for desc in cur.description]
        return cols, rows


def current_user():
    user = session.get("user")
    if user:
        mapping = {
            "admin": "Администратор",
            "manager": "Менеджер",
            "waiter": "Официант",
            "cook": "Шеф",
            "analyst": "Аналитик",
        }
        user["role_display"] = mapping.get(user.get("role"), user.get("role"))
    return user


def login_required(func):
    from functools import wraps

    @wraps(func)
    def wrapper(*args, **kwargs):
        if not current_user():
            return redirect(url_for("login"))
        return func(*args, **kwargs)

    return wrapper


def has_perm(module: str) -> bool:
    user = current_user()
    if not user:
        return False
    role = user.get("role")
    return module in ROLE_PERMISSIONS.get(role, set())

@app.route("/", methods=["GET"])
def index():
    if current_user():
        return redirect(url_for("dashboard"))
    return redirect(url_for("login"))


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        if not username or not password:
            flash("Заполните username и password", "danger")
            return render_template("login.html")
        try:
            with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute("SELECT id, username, password_hash FROM app_users WHERE username=%s", (username,))
                user = cur.fetchone()
                if not user:
                    flash("Пользователь не найден", "danger")
                    return render_template("login.html")
                stored = user.get("password_hash") or ""
                if not stored.startswith("$2") or not bcrypt.checkpw(password.encode("utf-8"), stored.encode("utf-8")):
                    flash("Неверный пароль или хеш не bcrypt", "danger")
                    return render_template("login.html")
                cur.execute(
                    """
                    SELECT ar.name, ur.restaurant_id
                    FROM app_user_roles ur
                    JOIN app_roles ar ON ar.id = ur.role_id
                    WHERE ur.user_id = %s
                    ORDER BY ar.name
                    """,
                    (user["id"],),
                )
                roles = cur.fetchall()
                if not roles:
                    flash("У пользователя нет ролей", "danger")
                    return render_template("login.html")
                role = roles[0]["name"]
                rest_id = roles[0]["restaurant_id"]
                session["user"] = {
                    "id": user["id"],
                    "username": user["username"],
                    "role": role,
                    "restaurant_id": rest_id,
                }
                with conn.cursor() as c2:
                    if role:
                        c2.execute("SELECT set_config('app.current_role', %s, true);", (role,))
                    if rest_id:
                        c2.execute("SELECT set_config('app.current_restaurant_id', %s, true);", (str(rest_id),))
            return redirect(url_for("dashboard"))
        except Exception as ex:
            flash(str(ex), "danger")
    return render_template("login.html")


@app.route("/signup", methods=["GET", "POST"])
def signup_waiter():
    if request.method == "POST":
        username = (request.form.get("username") or "").strip()
        password = request.form.get("password") or ""
        confirm = request.form.get("confirm") or ""
        rest = request.form.get("restaurant") or None
        role = (request.form.get("role") or "").strip()
        if not username or not password:
            flash("Заполните username и password", "danger")
            return redirect(url_for("signup_waiter"))
        if password != confirm:
            flash("Пароли не совпадают", "danger")
            return redirect(url_for("signup_waiter"))
        if not role:
            flash("Выберите роль", "danger")
            return redirect(url_for("signup_waiter"))
        if role == "admin":
            flash("Регистрация администратора запрещена", "danger")
            return redirect(url_for("signup_waiter"))
        try:
            pwd_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
            with get_db_conn() as conn, conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO app_users(username, password_hash) VALUES (%s, %s) RETURNING id",
                    (username, pwd_hash),
                )
                user_id = cur.fetchone()[0]
                cur.execute(
                    """
                    INSERT INTO app_user_roles(user_id, role_id, restaurant_id)
                    VALUES (%s, (SELECT id FROM app_roles WHERE name=%s), %s)
                    ON CONFLICT DO NOTHING
                    """,
                    (user_id, role, int(rest) if rest else None),
                )
            flash("Аккаунт создан. Войдите с новыми данными.", "success")
            return redirect(url_for("login"))
        except Exception as ex:
            flash(f"Ошибка регистрации: {ex}", "danger")
            return redirect(url_for("signup_waiter"))
    try:
        rests = list_restaurants()
        roles = list_roles_public()
    except Exception:
        rests = []
        roles = []
    return render_template("signup.html", restaurants=rests, roles=roles)


@app.route("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))

GOOGLE_SHEETS_CONFIG = {
    "credentials_file": "restaurants_secret.json",
    "spreadsheet_title": "Restaurant Analytics", }


def export_all_safe_tables_to_google_sheets():
    try:
        # Список таблиц с чувствительными данными — их НЕ выгружаем
        SENSITIVE_TABLES = {
            'app_users',
            'app_roles',
            'app_user_roles',
            'purchase_requests'
        }

        # Подключаемся к Google Sheets
        scopes = [
            "https://www.googleapis.com/auth/spreadsheets",
            "https://www.googleapis.com/auth/drive"
        ]
        creds = Credentials.from_service_account_file(
            GOOGLE_SHEETS_CONFIG["credentials_file"], scopes=scopes
        )
        client = gspread.authorize(creds)
        spreadsheet = client.open(GOOGLE_SHEETS_CONFIG["spreadsheet_title"])


        # Получаем список ВСЕХ таблиц
        with get_db_conn() as conn, conn.cursor() as cur:
            cur.execute("""
                        SELECT table_name
                        FROM information_schema.tables
                        WHERE table_schema = 'public'
                          AND table_type = 'BASE TABLE'
                        ORDER BY table_name;
                        """)
            all_tables = {row[0] for row in cur.fetchall()}

        # Фильтруем: только безопасные таблицы
        safe_tables = sorted(all_tables - SENSITIVE_TABLES)

        if not safe_tables:
            return False, "Нет безопасных таблиц для выгрузки"

        # Выгружаем каждую таблицу
        for table_name in safe_tables:
            try:
                # Пытаемся получить существующий лист
                worksheet = spreadsheet.worksheet(table_name)
            except gspread.exceptions.WorksheetNotFound:
                # Если нет — создаём
                worksheet = spreadsheet.add_worksheet(title=table_name, rows="1000", cols="26")

            # Получаем данные (с ограничением для безопасности)
            with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
                cur.execute(f"SELECT * FROM {table_name} LIMIT 5000")
                rows = cur.fetchall()

            if rows:
                # Заголовки + данные
                headers = list(rows[0].keys())
                data = [headers]
                for row in rows:
                    # Преобразуем всё в строки, None → пусто
                    data.append([str(v) if v is not None else "" for v in row.values()])

                worksheet.clear()
                worksheet.update("A1", data, value_input_option="USER_ENTERED")
            else:
                worksheet.clear()
                worksheet.update("A1", [["Таблица пуста"]])

        return True, f"Успешно выгружено {len(safe_tables)} таблиц: {', '.join(safe_tables)}"

    except Exception as e:
        return False, f"Ошибка выгрузки: {str(e)}, "


@app.route("/action/reports/export_all_safe_tables")
@login_required
def action_export_all_safe_tables():
    if not has_perm("admin"):  # Только админ!
        flash("Только админ может выгружать все таблицы", "danger")
        return redirect(url_for("dashboard") + "#tab-reports")

    success, msg = export_all_safe_tables_to_google_sheets()
    flash(msg, "success" if success else "danger")
    return redirect(url_for("dashboard") + "#tab-reports")

@app.route("/dashboard")
@login_required
def dashboard():
    user = current_user()
    data = {
        "permissions": ROLE_PERMISSIONS.get(user["role"], set()),
        "role": user["role"],
        "username": user["username"],
        "current_restaurant": user.get("restaurant_id"),
        "tables_form": session.get("tables_form"),
        "stocks_last": session.get("stocks_last"),
        "orders_last": session.get("orders_last"),
        "menu_last": session.get("menu_last"),
        "report_last": session.get("report_last"),
        "stats": get_counts(),
        "summary": [],
        "status_counts": [],
    }
    try:
        with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT id, name FROM restaurants ORDER BY id")
            data["restaurants"] = cur.fetchall()
            cur.execute("SELECT name FROM app_roles ORDER BY name")
            data["roles"] = [r["name"] for r in cur.fetchall()]
            data["tables"] = list_tables()
            form = data["tables_form"]
            if form and form.get("table"):
                form["columns"] = list_columns(form["table"])
                session["tables_form"] = form
            default_rest = data["restaurants"][0]["id"] if data["restaurants"] else None
            if not data["stocks_last"] and default_rest:
                data["stocks_last"] = list_stocks(default_rest)
                session["stocks_last"] = data["stocks_last"]
            if not data["orders_last"] and default_rest:
                data["orders_last"] = list_orders(default_rest, None)
                session["orders_last"] = data["orders_last"]
            if not data["menu_last"]:
                data["menu_last"] = list_dishes_filtered(default_rest, None, None, None, None, None)
                session["menu_last"] = data["menu_last"]
            if not data["report_last"]:
                cols, rows = run_report_default()
                data["report_last"] = {"cols": cols, "rows": rows, "key": "orders_per_restaurant"}
                session["report_last"] = data["report_last"]
            data["summary"] = get_summary(user["role"], data["current_restaurant"])
            data["status_counts"] = get_status_counts(user["role"], data["current_restaurant"])
            data["purchase_requests"] = list_purchase_requests(data["current_restaurant"])
    except Exception as ex:
        flash(f"Ошибка загрузки справочников: {ex}", "danger")
        data["restaurants"] = []
        data["roles"] = []
        data["tables"] = []
    return render_template("dashboard.html", **data)


def fetch_table(table: str, where: str | None, limit: int):
    sql = f"SELECT * FROM public.{table}"
    params = []
    if where:
        sql += f" WHERE {where}"
    sql += " ORDER BY 1 LIMIT %s"
    params.append(limit)
    with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
        cols = list(rows[0].keys()) if rows else []
        return cols, format_datetime_columns(rows)


@app.post("/action/tables/view")
@login_required
def action_tables_view():
    if not has_perm("tables"):
        flash("Нет доступа к таблицам", "warning")
        return redirect(url_for("dashboard") + "#tab-tables")
    table = (request.form.get("table", "") or "").strip()
    if table:
        form = session.get("tables_form")
        if form and form.get("table") != table:
            session.pop("tables_form", None)
    if not table:
        flash("Укажите имя таблицы", "warning")
        return redirect(url_for("dashboard") + "#tab-tables")
    where = request.form.get("where") or None
    limit = int(request.form.get("limit") or 200)
    try:
        cols, rows = fetch_table(table, where, limit)
        session["tables_last"] = {"table": table, "cols": cols, "rows": rows}
    except Exception as ex:
        flash(f"Ошибка чтения таблицы: {ex}", "danger")
    return redirect(url_for("dashboard") + "#tab-tables")


@app.post("/action/tables/insert")
@login_required
def action_tables_insert():
    if not has_perm("admin"):
        flash("Только админ может вставлять произвольно", "warning")
        return redirect(url_for("dashboard") + "#tab-tables")
    table = request.form.get("table_ins", "")
    payload = request.form.get("json_body", "") or ""
    try:
        import json
        if not payload.strip():
            raise ValueError("Нет данных для вставки")
        data = json.loads(payload)
        if not isinstance(data, dict):
            raise ValueError("Должен быть JSON-объект")
        cols = list(data.keys())
        vals = list(data.values())
        placeholders = ", ".join(["%s"] * len(cols))
        col_list = ", ". join(cols)
        sql = f"INSERT INTO public.{table} ({col_list}) VALUES ({placeholders})"
        with get_db_conn() as conn, conn.cursor() as cur:
            cur.execute(sql, vals)
        flash("Строка вставлена", "success")
        session.pop("tables_form", None)
    except Exception as ex:
        flash(f"Ошибка вставки: {ex}", "danger")
    return redirect(url_for("dashboard") + "#tab-tables")


@app.post("/action/tables/new_form")
@login_required
def action_tables_new_form():
    if not has_perm("admin"):
        flash("Нет доступа", "warning")
        return redirect(url_for("dashboard") + "#tab-tables")
    table = (request.form.get("table_form", "") or "").strip()
    if not table:
        flash("Укажите таблицу", "warning")
        return redirect(url_for("dashboard") + "#tab-tables")
    try:
        cols = list_columns(table)
        session["tables_form"] = {"table": table, "columns": cols}
        flash(f"Форма для {table} подготовлена", "info")
    except Exception as ex:
        flash(f"Ошибка подготовки формы: {ex}", "danger")
    return redirect(url_for("dashboard") + "#tab-tables")


@app.post("/action/users/create")
@login_required
def action_users_create():
    if not has_perm("admin"):
        flash("Нет доступа", "warning")
        return redirect(url_for("dashboard") + "#tab-users")
    username = (request.form.get("username") or "").strip()
    password = request.form.get("password") or ""
    confirm = request.form.get("confirm") or ""
    role = (request.form.get("role") or "").strip()
    rest = request.form.get("restaurant") or None
    if not username or not password or not role:
        flash("Заполните username, password и role", "warning")
        return redirect(url_for("dashboard") + "#tab-users")
    if password != confirm:
        flash("Пароли не совпадают", "warning")
        return redirect(url_for("dashboard") + "#tab-users")
    try:
        pwd_hash = bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
        with get_db_conn() as conn, conn.cursor() as cur:
            cur.execute(
                "INSERT INTO app_users(username, password_hash) VALUES (%s, %s) RETURNING id",
                (username, pwd_hash),
            )
            user_id = cur.fetchone()[0]
            cur.execute(
                """
                INSERT INTO app_user_roles(user_id, role_id, restaurant_id)
                VALUES (%s, (SELECT id FROM app_roles WHERE name=%s), %s)
                ON CONFLICT DO NOTHING
                """,
                (user_id, role, int(rest) if rest else None),
            )
        flash(f"Пользователь {username} создан", "success")
    except Exception as ex:
        flash(f"Ошибка создания пользователя: {ex}", "danger")
    return redirect(url_for("dashboard") + "#tab-users")


@app.post("/action/query/run")
@login_required
def action_query_run():
    if not has_perm("query"):
        flash("Нет доступа к SQL", "warning")
        return redirect(url_for("dashboard") + "#tab-query")
    sql = request.form.get("sql", "").strip()
    if not sql:
        flash("Запрос пустой", "warning")
        return redirect(url_for("dashboard") + "#tab-query")
    try:
        with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql)
            if cur.description:
                rows = cur.fetchall()
                cols = list(rows[0].keys()) if rows else [d.name for d in cur.description]
                session["query_last"] = {"cols": cols, "rows": rows}
                flash(f"Результат: {len(rows)} строк", "success")
            else:
                flash(f"OK, изменено строк: {cur.rowcount}", "success")
                session["query_last"] = None
    except Exception as ex:
        flash(f"Ошибка запроса: {ex}", "danger")
    return redirect(url_for("dashboard") + "#tab-query")


@app.post("/action/context/set")
@login_required
def action_context_set():
    role = request.form.get("role") or None
    rest = request.form.get("rest_id") or None
    try:
        user = session["user"]
        user["role"] = role
        user["restaurant_id"] = int(rest) if rest else None
        session["user"] = user
        with get_db_conn() as conn, conn.cursor() as cur:
            cur.execute("SELECT set_config('app.current_role', %s, true);", (role or "",))
            cur.execute("SELECT set_config('app.current_restaurant_id', %s, true);", (str(rest) if rest else "",))
        flash("Контекст обновлен", "success")
    except Exception as ex:
        flash(f"Ошибка контекста: {ex}", "danger")
    return redirect(url_for("dashboard") + "#tab-help")


@app.post("/action/inventory/update")
@login_required
def action_inventory_update():
    if not has_perm("inventory"):
        flash("Нет доступа к запасам", "warning")
        return redirect(url_for("dashboard") + "#tab-inv")
    ids_raw = request.form.get("selected_ids") or ""
    stock_ids = [i for i in ids_raw.split(",") if i.strip().isdigit()]
    qty = request.form.get("qty")
    expiry = request.form.get("expiry") or None
    if not stock_ids:
        flash("Выберите хотя бы одну позицию", "warning")
        return redirect(url_for("dashboard") + "#tab-inv")
    try:
        qty_val = float(qty) if qty else None
        sets = []
        params = []
        if qty_val is not None:
            sets.append("qty = %s")
            params.append(qty_val)
        if expiry:
            sets.append("expiry_date = %s")
            params.append(expiry)
        if not sets:
            flash("Нет данных для обновления", "info")
            return redirect(url_for("dashboard") + "#tab-inv")
        with get_db_conn() as conn, conn.cursor() as cur:
            for sid in stock_ids:
                cur.execute(f"UPDATE ingredient_batches SET {', '.join(sets)} WHERE id = %s", [*params, int(sid)])
        flash("Запасы обновлены", "success")
    except Exception as ex:
        flash(f"Ошибка обновления: {ex}", "danger")
    return redirect(url_for("dashboard") + "#tab-inv")


@app.post("/action/inventory/load")
@login_required
def action_inventory_load():
    if not has_perm("inventory"):
        flash("Нет доступа", "warning")
        return redirect(url_for("dashboard") + "#tab-inv")
    rest_id = request.form.get("rest_id") or None
    try:
        rows = list_stocks(int(rest_id)) if rest_id else list_stocks(None)
        session["stocks_last"] = rows
    except Exception as ex:
        flash(f"Ошибка загрузки запасов: {ex}", "danger")
    return redirect(url_for("dashboard") + "#tab-inv")


@app.post("/action/inventory/request")
@login_required
def action_inventory_request():
    if not has_perm("inventory"):
        flash("Нет доступа", "warning")
        return redirect(url_for("dashboard") + "#tab-inv")
    ids_raw = request.form.get("selected_ids") or ""
    stock_ids = [i for i in ids_raw.split(",") if i.strip().isdigit()]
    qty = (request.form.get("qty") or "").strip()
    if not stock_ids:
        flash("Выберите хотя бы одну позицию", "warning")
        return redirect(url_for("dashboard") + "#tab-inv")
    try:
        qty_val = float(qty) if qty else None
        with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(
                "SELECT id, restaurant_id, ingredient_id, min_threshold FROM ingredient_batches WHERE id = ANY(%s)",
                (list(map(int, stock_ids)),))
            rows = cur.fetchall()
            for row in rows:
                qty_to_use = qty_val if qty_val is not None else (row["min_threshold"] or 1)
                cur.execute(
                    "INSERT INTO purchase_requests(restaurant_id, ingredient_id, qty, status) VALUES (%s, %s, %s, 'new')",
                    (row["restaurant_id"], row["ingredient_id"], qty_to_use),
                )
        flash("Заявки созданы", "success")
    except Exception as ex:
        flash(f"Ошибка заявки: {ex}", "danger")
    return redirect(url_for("dashboard") + "#tab-inv")

def list_purchase_requests(restaurant_id: int | None = None) -> list[dict]:
    clauses = []
    params = []
    if restaurant_id:
        clauses.append("pr.restaurant_id = %s")
        params.append(restaurant_id)
    where_sql = "WHERE " + " AND ".join(clauses) if clauses else ""
    sql = f"""
        SELECT pr.id, pr.restaurant_id, i.name AS ingredient_name, pr.qty, pr.status, pr.created_at
        FROM purchase_requests pr
        JOIN ingredients i ON i.id = pr.ingredient_id
        {where_sql}
        ORDER BY pr.created_at DESC;
    """
    with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql, params)
        rows = cur.fetchall()
        return format_datetime_columns(rows)

@app.post("/action/orders/load")
@login_required
def action_orders_load():
    if not has_perm("orders"):
        flash("Нет доступа", "warning")
        return redirect(url_for("dashboard") + "#tab-orders")
    rest = request.form.get("rest_id") or None
    status = request.form.get("status") or None
    try:
        rows = list_orders(int(rest), status) if rest else list_orders(None, status)
        session["orders_last"] = rows
    except Exception as ex:
        flash(f"Ошибка загрузки заказов: {ex}", "danger")
    return redirect(url_for("dashboard") + "#tab-orders")


@app.post("/action/orders/create")
@login_required
def action_orders_create():
    if not has_perm("orders"):
        flash("Нет доступа", "warning")
        return redirect(url_for("dashboard") + "#tab-orders")

    rest_id = int(request.form.get("rest_id"))
    table_number = request.form.get("table") or None
    guest = request.form.get("guest") or None
    status = request.form.get("status") or "created"
    waiter = request.form.get("waiter") or None
    sched = request.form.get("scheduled") or None
    total = request.form.get("total") or None

    table_id = None
    if table_number:
        with get_db_conn() as conn, conn.cursor() as cur:
            cur.execute(
                "SELECT id FROM restaurant_tables WHERE restaurant_id = %s AND table_number = %s",
                (rest_id, table_number)
            )
            row = cur.fetchone()
            if row:
                table_id = row[0]

    try:
        with get_db_conn() as conn, conn.cursor() as cur:
            user = current_user()
            cur.execute(
                """
                INSERT INTO orders(restaurant_id, table_id, guest_name, status, created_by_user,
                                   scheduled_for, total_amount)
                VALUES (%s, %s, %s, %s, %s, %s, COALESCE(%s, 0)) RETURNING id
                """,
                (rest_id, table_id, guest, status, user["id"], sched, float(total) if total else None),
            )
            order_id = cur.fetchone()[0]
        flash(f"Заказ создан: {order_id}", "success")
    except Exception as ex:
        flash(f"Ошибка создания заказа: {ex}", "danger")
    return redirect(url_for("dashboard") + "#tab-orders")


@app.post("/action/orders/add_item")
@login_required
def action_orders_add_item():
    if not has_perm("orders"):
        flash("Нет доступа", "warning")
        return redirect(url_for("dashboard") + "#tab-orders")
    order_id = request.form.get("order_id")
    dish_id = request.form.get("dish_id")
    qty = request.form.get("qty")
    price = request.form.get("price")
    try:
        with get_db_conn() as conn, conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO order_items(order_id, dish_id, qty, price_at_order)
                VALUES (%s, %s, %s, %s)
                """,
                (order_id, int(dish_id), int(qty), float(price)),
            )
        flash("Позиция добавлена", "success")
    except Exception as ex:
        flash(f"Ошибка добавления позиции: {ex}", "danger")
    return redirect(url_for("dashboard") + "#tab-orders")


@app.post("/action/menu/filter")
@login_required
def action_menu_filter():
    if not has_perm("menu"):
        flash("Нет доступа", "warning")
        return redirect(url_for("dashboard") + "#tab-menu")
    rest = request.form.get("rest_id") or None
    category = request.form.get("category") or None
    avail = request.form.get("available") or None
    price_min = request.form.get("price_min") or None
    price_max = request.form.get("price_max") or None
    keyword = request.form.get("keyword") or None
    clauses = []
    params = []
    if rest:
        clauses.append("restaurant_id = %s")
        params.append(int(rest))
    if category:
        clauses.append("LOWER(category)=LOWER(%s)")
        params.append(category)
    if avail:
        clauses.append("is_available = %s")
        params.append(avail == "yes")
    if price_min:
        clauses.append("price >= %s")
        params.append(float(price_min))
    if price_max:
        clauses.append("price <= %s")
        params.append(float(price_max))
    if keyword:
        clauses.append("LOWER(name) LIKE LOWER(%s)")
        params.append(f"%{keyword}%")
    where_sql = "WHERE " + " AND ".join(clauses) if clauses else ""
    sql = f"""
        SELECT id, restaurant_id, name, category, price, prep_time_minutes, is_available
        FROM dishes
        {where_sql}
        ORDER BY restaurant_id, name
        LIMIT 200
    """
    try:
        with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, params)
            rows = cur.fetchall()
            session["menu_last"] = format_datetime_columns(rows)
    except Exception as ex:
        flash(f"Ошибка меню: {ex}", "danger")
    return redirect(url_for("dashboard") + "#tab-menu")


@app.post("/action/reports/run")
@login_required
def action_reports_run():
    if not has_perm("reports"):
        flash("Нет доступа", "warning")
        return redirect(url_for("dashboard") + "#tab-reports")
    key = request.form.get("report")
    rest = request.form.get("rest_id") or None
    try:
        sql = ""
        params = []
        if key == "orders_per_restaurant":
            sql = "SELECT restaurant_id, COUNT(*) AS orders_count, SUM(total_amount) AS total_amount FROM orders GROUP BY restaurant_id"
        elif key == "top_dishes":
            sql = """
                SELECT d.restaurant_id, d.name, SUM(oi.qty) AS total_qty
                FROM order_items oi JOIN dishes d ON d.id = oi.dish_id
                GROUP BY d.restaurant_id, d.name
                ORDER BY total_qty DESC
                LIMIT 20
            """
        elif key == "low_stock":
            sql = """
                SELECT s.restaurant_id, i.name, s.qty, s.min_threshold
                FROM ingredient_batches s JOIN ingredients i ON i.id = s.ingredient_id
                WHERE s.qty <= s.min_threshold
            """
        elif key == "expiring":
            sql = """
                SELECT s.restaurant_id, i.name, s.qty, s.expiry_date
                FROM ingredient_batches s JOIN ingredients i ON i.id = s.ingredient_id
                WHERE s.expiry_date IS NOT NULL AND s.expiry_date <= now()::date + INTERVAL '7 days'
            """
        elif key == "orders_by_status":
            sql = "SELECT status, COUNT(*) AS cnt FROM orders GROUP BY status"
        else:
            flash("Неизвестный отчет", "warning")
            return redirect(url_for("dashboard") + "#tab-reports")
        if rest and "restaurant_id" in sql:
            if "WHERE" in sql:
                sql += " AND restaurant_id = %s"
            else:
                sql += " WHERE restaurant_id = %s"
            params.append(int(rest))
        with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(sql, params)
            rows = cur.fetchall()
            cols = list(rows[0].keys()) if rows else [desc.name for desc in cur.description]
            session["report_last"] = {"cols": cols, "rows": rows, "key": key}
            rows = format_datetime_columns(rows)
            session["report_last"] = {"cols": cols, "rows": rows, "key": key}
    except Exception as ex:
        flash(f"Ошибка отчета: {ex}", "danger")
    return redirect(url_for("dashboard") + "#tab-reports")


import csv
from io import StringIO


@app.route("/api/reports/top_dishes.csv")
@login_required
def report_top_dishes_csv():
    if not has_perm("reports"):
        return "Доступ запрещён", 403

    with get_db_conn() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute("""
                    SELECT r.name AS restaurant, d.name AS dish, SUM(oi.qty) AS total
                    FROM order_items oi
                             JOIN dishes d ON oi.dish_id = d.id
                             JOIN orders o ON oi.order_id = o.id
                             JOIN restaurants r ON o.restaurant_id = r.id
                    WHERE o.status = 'completed'
                    GROUP BY r.name, d.name
                    ORDER BY total DESC LIMIT 20;
                    """)
        rows = cur.fetchall()

    output = StringIO()
    writer = csv.writer(output)
    writer.writerow(["Ресторан", "Блюдо", "Продано"])
    for row in rows:
        writer.writerow(row.values())

    output.seek(0)
    return Response(
        output.getvalue(),
        mimetype="text/csv",
        headers={"Content-Disposition": "attachment; filename=top_dishes.csv"}
    )

if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=8000)