# app/security/sql_guard.py
import re
from app.security.rule_based import rule_based_check, normalize_sql
from app.security.ml_guard import MLSQLGuard

# Whitelist для известных безопасных запросов (нормализованные)
SAFE_QUERY_WHITELIST = [
    # Простые SELECT запросы
    r"^\s*select\s+\*\s+from\s+\w+\s*;?\s*$",
    r"^\s*select\s+[\w\s,]+from\s+\w+\s*;?\s*$",
    r"^\s*select\s+[\w\s,]+from\s+\w+\s+where\s+[\w\s=<>'\"()]+;?\s*$",
    # SELECT с LIMIT
    r"^\s*select\s+.*?\s+from\s+\w+\s+limit\s+\d+\s*;?\s*$",
    # SELECT с ORDER BY
    r"^\s*select\s+.*?\s+from\s+\w+\s+order\s+by\s+\w+\s*;?\s*$",
    # WITH запросы
    r"^\s*with\s+\w+\s+as\s*\(.*?\)\s*select\s+.*?\s*;?\s*$",
    # EXPLAIN запросы
    r"^\s*explain\s+(analyze\s+)?\s*select\s+.*?\s*;?\s*$",
]

def is_whitelisted(sql: str) -> bool:
    """Проверяет, находится ли запрос в whitelist безопасных паттернов"""
    # Сначала проверяем, нет ли опасных команд в комментариях
    # Извлекаем комментарии перед нормализацией
    sql_lower = sql.lower()
    
    # Проверяем однострочные комментарии
    single_line_comments = re.findall(r'--.*?$', sql, re.MULTILINE)
    for comment in single_line_comments:
        # Если в комментарии есть опасные команды, не пропускаем через whitelist
        dangerous_in_comment = re.search(r'\b(drop|delete|truncate|alter|create|insert|update|exec|execute|union|or\s+1\s*=\s*1)\b', comment, re.IGNORECASE)
        if dangerous_in_comment:
            return False
    
    # Проверяем многострочные комментарии
    multi_line_comments = re.findall(r'/\*.*?\*/', sql, re.DOTALL)
    for comment in multi_line_comments:
        dangerous_in_comment = re.search(r'\b(drop|delete|truncate|alter|create|insert|update|exec|execute|union|or\s+1\s*=\s*1)\b', comment, re.IGNORECASE)
        if dangerous_in_comment:
            return False
    
    # Теперь проверяем whitelist на нормализованном SQL
    normalized = normalize_sql(sql).lower()
    for pattern in SAFE_QUERY_WHITELIST:
        if re.match(pattern, normalized, re.IGNORECASE | re.DOTALL):
            return True
    return False

def validate_sql_structure(sql: str) -> tuple[bool, str]:
    """Дополнительная валидация структуры SQL"""
    normalized = normalize_sql(sql)
    s = normalized.lower()
    
    # Проверка на слишком длинные запросы (возможная инъекция)
    if len(normalized) > 10000:
        return False, "Query too long (possible injection attempt)"
    
    # Проверка на подозрительные символы (но разрешаем нормальные переносы строк)
    # Блокируем только действительно опасные символы: NULL, SUB (substitute), но не \n и \r
    suspicious_chars = ['\x00', '\x1a']  # NULL и SUB (substitute)
    for char in suspicious_chars:
        if char in sql:
            return False, f"Suspicious character detected: {repr(char)}"
    
    # Проверка на экранированные кавычки (возможная инъекция)
    if sql.count("'") > 20 or sql.count('"') > 20:
        return False, "Too many quotes (possible injection attempt)"
    
    return True, ""

def validate_sql(sql: str) -> dict:
    # 0. Проверка whitelist (быстрый путь для безопасных запросов)
    if is_whitelisted(sql):
        return {"allowed": True, "layer": "whitelist"}
    
    # 0.5. Дополнительная валидация структуры
    struct_valid, struct_reason = validate_sql_structure(sql)
    if not struct_valid:
        return {
            "allowed": False,
            "layer": "structure_validation",
            "reason": struct_reason
        }
    
    # 1. Rule-based
    blocked, reason = rule_based_check(sql)
    if blocked:
        return {
            "allowed": False,
            "layer": "rule_based",
            "reason": reason
        }

    # 2. ML (только если прошли rule-based)
    guard = MLSQLGuard.instance()
    malicious, score = guard.check(sql)
    if malicious:
        # Дополнительная проверка: если score близок к порогу, 
        # но запрос выглядит безопасно по структуре, можем быть более мягкими
        # Но для безопасности лучше блокировать
        return {
            "allowed": False,
            "layer": "ml",
            "risk_score": round(score, 4)
        }

    return {"allowed": True}
