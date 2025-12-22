import re
from app.security.rule_based import rule_based_check, normalize_sql
from app.security.ml_guard import MLSQLGuard

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
    single_line_comments = re.findall(r'--.*?$', sql, re.MULTILINE)
    for comment in single_line_comments:
        dangerous_in_comment = re.search(
            r'\b(drop|delete|truncate|alter|create|insert|update|exec|execute|union|or\s+1\s*=\s*1)\b', 
            comment, 
            re.IGNORECASE
        )
        if dangerous_in_comment:
            return False

    multi_line_comments = re.findall(r'/\*.*?\*/', sql, re.DOTALL)
    for comment in multi_line_comments:
        dangerous_in_comment = re.search(
            r'\b(drop|delete|truncate|alter|create|insert|update|exec|execute|union|or\s+1\s*=\s*1)\b', 
            comment, 
            re.IGNORECASE
        )
        if dangerous_in_comment:
            return False

    normalized = normalize_sql(sql).lower()

    for pattern in SAFE_QUERY_WHITELIST:
        if re.match(pattern, normalized, re.IGNORECASE | re.DOTALL):
            return True
    
    return False

def validate_sql_structure(sql: str) -> tuple[bool, str]:
    normalized = normalize_sql(sql)
    s = normalized.lower()
    
    if len(normalized) > 10000:
        return False, "Query too long (possible injection attempt)"

    suspicious_chars = ['\x00', '\x1a']  # NULL и SUB (substitute)
    for char in suspicious_chars:
        if char in sql:
            return False, f"Suspicious character detected: {repr(char)}"
    
    if sql.count("'") > 20 or sql.count('"') > 20:
        return False, "Too many quotes (possible injection attempt)"
    
    return True, ""

def validate_sql(sql: str) -> dict:
    if is_whitelisted(sql):
        return {"allowed": True, "layer": "whitelist"}
    struct_valid, struct_reason = validate_sql_structure(sql)
    if not struct_valid:
        return {
            "allowed": False,
            "layer": "structure_validation",
            "reason": struct_reason
        }

    blocked, reason = rule_based_check(sql)
    if blocked:
        return {
            "allowed": False,
            "layer": "rule_based",
            "reason": reason
        }
    guard = MLSQLGuard.instance()
    malicious, score = guard.check(sql)
    if malicious:
        return {
            "allowed": False,
            "layer": "ml",
            "risk_score": round(score, 4)
        }
    return {"allowed": True}
