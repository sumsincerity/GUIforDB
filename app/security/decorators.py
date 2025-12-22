# app/security/decorators.py
from functools import wraps
from flask import request, jsonify
from app.security.sql_guard import validate_sql

def protect_sql(get_sql):
    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            sql = get_sql(request)
            if sql:
                result = validate_sql(sql)
                if not result["allowed"]:
                    return jsonify({
                        "error": "SQL blocked",
                        **result
                    }), 403
            return fn(*args, **kwargs)
        return wrapper
    return decorator
