function dbq --description 'Run SQL on Databricks cluster via Databricks Connect'
    # dbq "select * from t where id = :id" -p id=42 [-n 500]   (or pipe SQL via stdin)
    _dbx_ensure_cluster; or return 1
    set -l code '
import argparse, sys
from databricks.connect import DatabricksSession
ap = argparse.ArgumentParser(prog="dbq")
ap.add_argument("query", nargs="?")
ap.add_argument("-p", "--param", action="append", default=[])
ap.add_argument("-n", "--rows", type=int, default=100)
a = ap.parse_args()
query = a.query or sys.stdin.read()
params = dict(p.split("=", 1) for p in a.param)
spark = DatabricksSession.builder.getOrCreate()
spark.sql(query, args=params or None).show(a.rows, truncate=False)
'
    $DBX_VENV/bin/python -c $code $argv
end

