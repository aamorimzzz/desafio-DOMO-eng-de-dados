"""
Ingestão — Camada BRONZE
========================
Lê o arquivo de origem (finbank_dirty.xlsx) e aterrissa cada aba na camada
Bronze de um banco DuckDB, SEM nenhuma transformação ou limpeza.

Princípio da camada Bronze:
- Raw imutável: o dado é persistido exatamente como veio da origem (sujeira inclusa).
- Apenas metadados técnicos de ingestão são adicionados (_ingested_at, _source_file).
- A limpeza acontece somente na camada Silver, a partir do Bronze — garantindo
  rastreabilidade e reprocessamento sem necessidade de reextrair da origem.

Em produção (Databricks/Azure), esta etapa seria um job PySpark gravando em
tabelas Delta na zona Bronze do Data Lake. Aqui usamos pandas + DuckDB pela
escala da base (~1.6k linhas) e portabilidade.
"""

from datetime import datetime, timezone
from pathlib import Path

import duckdb
import pandas as pd

# Caminhos relativos à raiz do projeto
ROOT = Path(__file__).resolve().parents[1]
SOURCE_XLSX = ROOT / "data" / "raw" / "finbank_dirty.xlsx"
DB_PATH = ROOT / "transform" / "finbank.duckdb"

# Mapeamento aba -> tabela bronze
SHEETS = ["clientes", "transacoes", "cartao"]


def ingest() -> None:
    if not SOURCE_XLSX.exists():
        raise FileNotFoundError(f"Origem não encontrada: {SOURCE_XLSX}")

    ingested_at = datetime.now(timezone.utc)
    con = duckdb.connect(str(DB_PATH))
    con.execute("CREATE SCHEMA IF NOT EXISTS bronze;")

    print(f"[ingest] origem: {SOURCE_XLSX.name}")
    print(f"[ingest] destino: {DB_PATH.name} (schema bronze)\n")

    for sheet in SHEETS:
        df = pd.read_excel(SOURCE_XLSX, sheet_name=sheet)

        # Metadados técnicos de ingestão — NÃO alteram o dado de negócio
        df["_ingested_at"] = ingested_at
        df["_source_file"] = SOURCE_XLSX.name

        table = f"bronze.{sheet}"
        con.register("df_tmp", df)
        con.execute(f"CREATE OR REPLACE TABLE {table} AS SELECT * FROM df_tmp")
        con.unregister("df_tmp")

        n = con.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
        print(f"[ingest] {table:<22} -> {n:>5} linhas (raw, sem tratamento)")

    con.close()
    print("\n[ingest] Bronze concluído. Nenhuma limpeza aplicada (by design).")


if __name__ == "__main__":
    ingest()
