function dbp --description 'Run Python with a `spark` session on Databricks cluster'
    # dbp script.py | dbp -c "spark.table(...).show()" | echo "..." | dbp
    _dbx_ensure_cluster; or return 1
    set -l code '
import sys
from databricks.connect import DatabricksSession
spark = DatabricksSession.builder.getOrCreate()
if len(sys.argv) > 2 and sys.argv[1] == "-c":
    code = sys.argv[2]
elif len(sys.argv) > 1:
    code = open(sys.argv[1]).read()
else:
    code = sys.stdin.read()
exec(compile(code, "<dbp>", "exec"), {"spark": spark, "__name__": "__main__"})
'
    $DBX_VENV/bin/python -c $code $argv
end

