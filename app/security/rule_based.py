import re

DANGEROUS_PATTERNS = [
    r";\s*--",
    r"/\*.*?\*/",
    # UNION-based injection
    r"\bunion\b\s+all\s+\bselect\b",
    r"\bunion\b\s+\bselect\b.*?\bfrom\b.*?\bwhere\b.*?\b1\s*=\s*1\b",
    # Boolean-based injection
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
    # Hex encoding
    r"0x[0-9a-f]+.*?\bunion\b",
]

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

# Whitelist
SAFE_PATTERNS = [
    r"^\s*select\s+.*?\s+from\s+",
    r"^\s*with\s+\w+\s+as\s*\(",
    r"^\s*explain\s+(analyze\s+)?\s*select\s+",
]

def normalize_sql(sql: str) -> str:
    sql = re.sub(r"--.*?$", "", sql, flags=re.MULTILINE)
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.DOTALL)
    
    sql = re.sub(r'\s+', ' ', sql)
    
    return sql.strip()

def rule_based_check(sql: str) -> tuple[bool, str]:
    normalized = normalize_sql(sql)
    s = normalized.lower().strip()
    
    if not s:
        return True, "Empty query after normalization"
    
    if s.count(';') > 1 or (s.count(';') == 1 and not s.endswith(';')):
        parts = [p.strip() for p in s.split(';') if p.strip()]
        if len(parts) > 1:
            return True, "Multiple statements detected (stacked queries)"
    
    starts_with_safe = any(s.startswith(prefix) for prefix in SAFE_PREFIXES)
    if not starts_with_safe:
        return True, "Non-SELECT statement is forbidden"

    for kw in FORBIDDEN_KEYWORDS:
        pattern = rf'(^|\s|;)\b{re.escape(kw)}\b(\s|\(|;|$)'
        if re.search(pattern, s, re.IGNORECASE):
            if not any(ctx in s for ctx in ["information_schema", "pg_catalog"]):
                kw_pos = s.find(kw)
                if kw_pos > 0:
                    before = s[:kw_pos].rstrip()
                    if before.count("'") % 2 == 1 or before.count('"') % 2 == 1:
                        continue
                return True, f"Forbidden keyword used as command: {kw}"
    
    for pattern in DANGEROUS_PATTERNS:
        if re.search(pattern, s, re.IGNORECASE):
            return True, f"Matched dangerous pattern: {pattern}"

    if s.startswith("select"):
        pass
    
    return False, ""
