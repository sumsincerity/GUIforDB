# app/security/rule_based.py
import re

# Явные сигнатуры атак
DANGEROUS_PATTERNS = [
    # Комментарии SQL injection
    r";\s*--",
    r"/\*.*?\*/",
    # UNION-based injection
    r"\bunion\b\s+all\s+\bselect\b",
    r"\bunion\b\s+\bselect\b.*?\bfrom\b.*?\bwhere\b.*?\b1\s*=\s*1\b",
    # Boolean-based injection (более точные паттерны)
    r"\bor\b\s+['\"]?\d+['\"]?\s*=\s*['\"]?\d+['\"]?\s*--",
    r"\bor\b\s+['\"]?1['\"]?\s*=\s*['\"]?1['\"]?\s*--",
    r"\band\b\s+['\"]?\d+['\"]?\s*=\s*['\"]?\d+['\"]?\s*--",
    # Time-based injection
    r"\bpg_sleep\b\s*\(",
    r"\bsleep\b\s*\(",
    r"\bwaitfor\b\s+delay\b",
    # Command execution
    r"\bxp_cmdshell\b",
    r"\bexec\b\s*\(.*?xp_cmdshell",
    r"\bexecute\b\s*\(.*?xp_cmdshell",
    # Stacked queries
    r";\s*\b(insert|update|delete|drop|create|alter|truncate)\b",
    # Information schema exploitation
    r"\binformation_schema\b.*?\bunion\b",
    # Hex encoding attempts
    r"0x[0-9a-f]+.*?\bunion\b",
]

# Запрещённые команды (в UI) - только как отдельные слова
FORBIDDEN_KEYWORDS = {
    "drop",
    "truncate",
    "alter",
    "grant",
    "revoke",
    "copy",
    "create",
    "delete",
    "update",
    "insert",
}

SAFE_PREFIXES = (
    "select",
    "with",
    "explain",
)

# Whitelist для безопасных паттернов (чтобы избежать ложных срабатываний)
SAFE_PATTERNS = [
    r"^\s*select\s+.*?\s+from\s+",
    r"^\s*with\s+\w+\s+as\s*\(",
    r"^\s*explain\s+(analyze\s+)?\s*select\s+",
]

def normalize_sql(sql: str) -> str:
    """Нормализует SQL для проверки"""
    # Удаляем комментарии (однострочные и многострочные)
    sql = re.sub(r"--.*?$", "", sql, flags=re.MULTILINE)
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.DOTALL)
    
    # Нормализуем пробелы
    sql = re.sub(r'\s+', ' ', sql)
    
    return sql.strip()

def rule_based_check(sql: str) -> tuple[bool, str]:
    # Нормализуем SQL
    normalized = normalize_sql(sql)
    s = normalized.lower().strip()
    
    # Проверка на пустой запрос после нормализации
    if not s:
        return True, "Empty query after normalization"
    
    # Проверка на множественные запросы (stacked queries)
    if s.count(';') > 1 or (s.count(';') == 1 and not s.endswith(';')):
        # Разрешаем только один SELECT с точкой с запятой в конце
        parts = [p.strip() for p in s.split(';') if p.strip()]
        if len(parts) > 1:
            return True, "Multiple statements detected (stacked queries)"
    
    # Проверка на безопасные префиксы
    starts_with_safe = any(s.startswith(prefix) for prefix in SAFE_PREFIXES)
    if not starts_with_safe:
        return True, "Non-SELECT statement is forbidden"
    
    # Проверка на запрещённые ключевые слова (только как SQL команды, не как часть идентификаторов)
    # Проверяем, что запрещённые слова используются как команды (после точки с запятой, начала строки или ключевых слов)
    for kw in FORBIDDEN_KEYWORDS:
        # Ищем ключевое слово как отдельное слово, но не как часть идентификатора
        # Паттерн: начало строки/пробел/точка с запятой + ключевое слово + пробел/скобка/точка с запятой
        pattern = rf'(^|\s|;)\b{re.escape(kw)}\b(\s|\(|;|$)'
        if re.search(pattern, s, re.IGNORECASE):
            # Исключение: если это часть безопасного контекста (например, information_schema)
            # или это часть имени таблицы/колонки в кавычках
            if not any(ctx in s for ctx in ["information_schema", "pg_catalog"]):
                # Проверяем, не является ли это частью строки в кавычках
                # Простая проверка: если перед ключевым словом есть кавычка, это может быть имя
                kw_pos = s.find(kw)
                if kw_pos > 0:
                    before = s[:kw_pos].rstrip()
                    # Если перед ключевым словом есть открывающая кавычка без закрывающей, это может быть имя
                    if before.count("'") % 2 == 1 or before.count('"') % 2 == 1:
                        continue  # Пропускаем, это часть строки
                return True, f"Forbidden keyword used as command: {kw}"
    
    # Проверка опасных паттернов
    for pattern in DANGEROUS_PATTERNS:
        if re.search(pattern, s, re.IGNORECASE):
            return True, f"Matched dangerous pattern: {pattern}"
    
    # Дополнительная проверка: убеждаемся, что это действительно SELECT-подобный запрос
    # Проверяем базовую структуру (но разрешаем подзапросы без явного FROM)
    if s.startswith("select"):
        # Базовый SELECT должен иметь FROM или быть подзапросом
        # Но не будем слишком строгими, так как могут быть подзапросы
        pass  # Убрали строгую проверку, так как подзапросы могут не иметь FROM
    
    return False, ""
