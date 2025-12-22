# app/security/ml_guard.py
import joblib
import threading
import re

class MLSQLGuard:
    _instance = None
    _lock = threading.Lock()

    def __init__(self):
        self.model = joblib.load("sql_injection_model.pkl")
        self.threshold = 0.7367346938775511
        # Более строгий порог для подозрительных случаев
        self.strict_threshold = 0.65

    @classmethod
    def instance(cls):
        if not cls._instance:
            with cls._lock:
                if not cls._instance:
                    cls._instance = cls()
        return cls._instance

    def _has_suspicious_features(self, sql: str) -> bool:
        """Проверяет наличие подозрительных признаков, которые требуют более строгой проверки"""
        s = sql.lower()
        
        # Подозрительные паттерны, которые требуют более низкого порога
        suspicious = [
            r"union.*select",
            r"or\s+1\s*=\s*1",
            r"and\s+1\s*=\s*1",
            r"exec\s*\(",
            r"execute\s*\(",
            r"pg_sleep",
            r"sleep\s*\(",
            r"information_schema",
            r"0x[0-9a-f]+",
            r"--",
            r"/\*",
        ]
        
        for pattern in suspicious:
            if re.search(pattern, s, re.IGNORECASE):
                return True
        
        # Подозрительное количество специальных символов
        special_chars = sum(1 for c in sql if c in "()[]{}\"'`;")
        if special_chars > 20:
            return True
        
        return False

    def check(self, sql: str) -> tuple[bool, float]:
        """
        Проверяет SQL запрос с помощью ML модели.
        Возвращает (is_malicious, risk_score)
        """
        try:
            proba = self.model.predict_proba([sql])[0][1]
            
            # Если есть подозрительные признаки, используем более строгий порог
            threshold = self.strict_threshold if self._has_suspicious_features(sql) else self.threshold
            
            is_malicious = proba >= threshold
            
            return is_malicious, proba
        except Exception as e:
            # В случае ошибки модели, лучше заблокировать (fail-safe)
            # Но можно логировать для отладки
            return True, 1.0
