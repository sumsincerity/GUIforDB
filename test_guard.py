#!/usr/bin/env python3
"""
Скрипт для тестирования guard системы на запросах из requests.txt
"""
import re
from app.security.sql_guard import validate_sql

def extract_sql_queries(file_path: str) -> list[tuple[str, str]]:
    """Извлекает SQL запросы из файла requests.txt"""
    queries = []
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    current_description = ""
    current_sql = ""
    
    for line in lines:
        line_stripped = line.strip()
        
        # Пропускаем пустые строки
        if not line_stripped:
            continue
        
        # Проверяем, является ли строка описанием (начинается с цифры и точки/скобки)
        if re.match(r'^\d+[\.\)]\s', line_stripped):
            # Сохраняем предыдущий запрос, если есть
            if current_sql:
                queries.append((current_description, current_sql.strip()))
                current_sql = ""
            
            # Извлекаем описание
            current_description = re.sub(r'^\d+[\.\)]\s*', '', line_stripped)
            continue
        
        # Если это SQL запрос (начинается с ключевого слова)
        if re.match(r'^\s*(SELECT|WITH|EXPLAIN|INSERT|UPDATE|DELETE|CREATE|ALTER|DROP|TRUNCATE)', line_stripped, re.IGNORECASE):
            current_sql = line_stripped
        elif current_sql:
            # Продолжение SQL запроса (в новом формате запросы в одну строку, но на всякий случай)
            current_sql += " " + line_stripped
    
    # Сохраняем последний запрос
    if current_sql:
        queries.append((current_description, current_sql.strip()))
    
    # Разделяем множественные запросы в одном блоке
    final_queries = []
    for desc, sql in queries:
        # Разделяем по точкам с запятой, но учитываем, что они могут быть в строках
        parts = []
        current_part = []
        in_string = False
        string_char = None
        
        for char in sql:
            if char in ("'", '"') and (not current_part or current_part[-1] != '\\'):
                if not in_string:
                    in_string = True
                    string_char = char
                elif char == string_char:
                    in_string = False
                    string_char = None
            
            current_part.append(char)
            
            if char == ';' and not in_string:
                part = ''.join(current_part).strip()
                if part:
                    parts.append(part)
                current_part = []
        
        # Добавляем последнюю часть
        if current_part:
            part = ''.join(current_part).strip()
            if part:
                parts.append(part)
        
        # Если запросов несколько, добавляем каждый отдельно
        if len(parts) > 1:
            for i, part in enumerate(parts):
                final_queries.append((f"{desc} (запрос {i+1})", part))
        else:
            final_queries.append((desc, sql))
    
    return final_queries

def test_queries(queries: list[tuple[str, str]]):
    """Тестирует запросы через guard систему"""
    results = {
        'allowed': [],
        'blocked': [],
        'errors': []
    }
    
    print("=" * 80)
    print("ТЕСТИРОВАНИЕ GUARD СИСТЕМЫ")
    print("=" * 80)
    print()
    
    for i, (description, sql) in enumerate(queries, 1):
        if not sql.strip():
            continue
            
        print(f"[{i}] {description}")
        print(f"SQL: {sql[:100]}{'...' if len(sql) > 100 else ''}")
        
        try:
            result = validate_sql(sql)
            
            if result['allowed']:
                layer = result.get('layer', 'unknown')
                print(f"✅ РАЗРЕШЕН (слой: {layer})")
                results['allowed'].append((description, sql, result))
            else:
                layer = result.get('layer', 'unknown')
                reason = result.get('reason', result.get('risk_score', 'N/A'))
                print(f"❌ ЗАБЛОКИРОВАН (слой: {layer}, причина: {reason})")
                results['blocked'].append((description, sql, result))
        except Exception as e:
            print(f"⚠️  ОШИБКА: {e}")
            results['errors'].append((description, sql, str(e)))
        
        print("-" * 80)
        print()
    
    # Итоговая статистика
    print("=" * 80)
    print("ИТОГОВАЯ СТАТИСТИКА")
    print("=" * 80)
    print(f"Всего запросов: {len(queries)}")
    print(f"✅ Разрешено: {len(results['allowed'])}")
    print(f"❌ Заблокировано: {len(results['blocked'])}")
    print(f"⚠️  Ошибок: {len(results['errors'])}")
    print()
    
    # Детали по заблокированным
    if results['blocked']:
        print("ЗАБЛОКИРОВАННЫЕ ЗАПРОСЫ:")
        print("-" * 80)
        for desc, sql, result in results['blocked']:
            layer = result.get('layer', 'unknown')
            reason = result.get('reason', result.get('risk_score', 'N/A'))
            print(f"  • {desc}")
            print(f"    Слой: {layer}, Причина: {reason}")
            print(f"    SQL: {sql[:80]}...")
            print()
    
    # Детали по ошибкам
    if results['errors']:
        print("ОШИБКИ:")
        print("-" * 80)
        for desc, sql, error in results['errors']:
            print(f"  • {desc}")
            print(f"    Ошибка: {error}")
            print(f"    SQL: {sql[:80]}...")
            print()
    
    return results

def get_malicious_test_queries() -> list[tuple[str, str]]:
    """Возвращает набор вредоносных запросов для тестирования защиты"""
    return [
        # UNION-based injection
        ("UNION SELECT injection", "SELECT * FROM users WHERE id = 1 UNION SELECT * FROM passwords"),
        ("UNION ALL SELECT", "SELECT * FROM orders UNION ALL SELECT * FROM users"),
        
        # Boolean-based injection
        ("OR 1=1 injection", "SELECT * FROM users WHERE id = 1 OR 1=1 --"),
        ("AND 1=1 injection", "SELECT * FROM users WHERE id = 1 AND 1=1 --"),
        
        # Comment-based injection
        ("Comment injection", "SELECT * FROM users; -- DROP TABLE users"),
        ("Multi-line comment", "SELECT * FROM users /* DROP TABLE users */"),
        
        # Stacked queries
        ("Stacked query DROP", "SELECT * FROM users; DROP TABLE users;"),
        ("Stacked query INSERT", "SELECT * FROM users; INSERT INTO users VALUES (1, 'hacker');"),
        
        # Time-based injection
        ("Time-based pg_sleep", "SELECT * FROM users WHERE id = 1; SELECT pg_sleep(5);"),
        ("Time-based sleep", "SELECT * FROM users WHERE id = 1 OR sleep(5)"),
        
        # Command execution
        ("xp_cmdshell", "SELECT * FROM users; EXEC xp_cmdshell('dir');"),
        ("Execute command", "SELECT * FROM users; EXECUTE('rm -rf /');"),
        
        # Information schema exploitation
        ("Information schema UNION", "SELECT * FROM users UNION SELECT * FROM information_schema.tables"),
        
        # Hex encoding
        ("Hex encoding", "SELECT * FROM users WHERE id = 0x31 UNION SELECT * FROM passwords"),
        
        # Forbidden keywords
        ("DROP TABLE", "DROP TABLE users"),
        ("TRUNCATE", "TRUNCATE TABLE orders"),
        ("ALTER TABLE", "ALTER TABLE users ADD COLUMN hacked BOOLEAN"),
        ("DELETE", "DELETE FROM users WHERE 1=1"),
        ("UPDATE", "UPDATE users SET password = 'hacked'"),
        ("INSERT", "INSERT INTO users VALUES (999, 'hacker')"),
        
        # Non-SELECT statements
        ("CREATE TABLE", "CREATE TABLE hacked (id INT)"),
        ("GRANT", "GRANT ALL ON users TO public"),
    ]

if __name__ == '__main__':
    import sys
    
    # Проверяем аргументы командной строки
    test_malicious = '--malicious' in sys.argv or '-m' in sys.argv
    test_requests = '--requests' in sys.argv or '-r' in sys.argv or len(sys.argv) == 1
    
    all_queries = []
    
    # Тестируем запросы из requests.txt
    if test_requests:
        queries = extract_sql_queries('requests.txt')
        print(f"Найдено {len(queries)} SQL запросов из requests.txt")
        all_queries.extend(queries)
        print()
    
    # Тестируем вредоносные запросы
    if test_malicious:
        malicious = get_malicious_test_queries()
        print(f"Добавлено {len(malicious)} вредоносных запросов для тестирования")
        all_queries.extend(malicious)
        print()
    
    if not all_queries:
        print("Использование:")
        print("  python test_guard.py              # Тестировать запросы из requests.txt")
        print("  python test_guard.py --malicious  # Тестировать только вредоносные запросы")
        print("  python test_guard.py --requests --malicious  # Тестировать все")
        sys.exit(1)
    
    # Тестируем
    results = test_queries(all_queries)

