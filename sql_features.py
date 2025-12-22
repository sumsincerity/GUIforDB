import re
import pandas as pd
from sklearn.base import BaseEstimator, TransformerMixin

SQL_KEYWORDS = [
    "select", "union", "insert", "update", "delete",
    "drop", "sleep", "pg_sleep", "benchmark",
    "--", "/*", "*/", ";",
    "or", "and", "information_schema"
]

def extract_features(query: str):
    q = str(query).lower()
    num_keywords = sum(1 for k in SQL_KEYWORDS if k in q)
    return {
        "length": len(q),
        "num_quotes": q.count("'") + q.count('"'),
        "num_comments": len(re.findall(r"--|/\*|\*/", q)),
        "num_semicolons": q.count(";"),
        "has_union": int("union select" in q),
        "has_or_true": int(bool(re.search(r"or\s+1\s*=\s*1", q))),
        "num_keywords": num_keywords,
        "special_char_ratio": sum(c in "'\";-" for c in q) / max(len(q), 1),
        "num_sleep": int(bool(re.search(r"sleep|pg_sleep|benchmark", q))),
        "num_subqueries": q.count("(") - q.count(")")
    }

class FeatureExtractor(BaseEstimator, TransformerMixin):
    def fit(self, X, y=None):
        return self

    def transform(self, X):
        return pd.DataFrame([extract_features(q) for q in X])
