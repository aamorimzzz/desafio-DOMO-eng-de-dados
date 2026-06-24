"""
API de consumo da camada Gold
=============================
Expõe os dados curados da camada Gold via HTTP, simulando o consumo por
aplicações downstream. A API lê o DuckDB em modo somente-leitura: consome
o resultado do pipeline, não o altera.

Rodar:
    uvicorn api.main:app --reload
Documentação interativa em http://localhost:8000/docs
"""

from pathlib import Path

import duckdb
from fastapi import FastAPI, HTTPException

DB_PATH = Path(__file__).resolve().parents[1] / "transform" / "finbank.duckdb"

app = FastAPI(
    title="FinBank — API de Consumo (Gold)",
    description="Acesso aos dados curados da camada Gold do pipeline.",
    version="1.0.0",
)


def query(sql: str, params: list | None = None) -> list[dict]:
    """Executa uma consulta read-only no DuckDB e devolve lista de dicts."""
    if not DB_PATH.exists():
        raise HTTPException(
            status_code=503,
            detail="Banco não encontrado. Rode o pipeline antes (ingest + dbt build).",
        )
    con = duckdb.connect(str(DB_PATH), read_only=True)
    try:
        cur = con.execute(sql, params or [])
        cols = [c[0] for c in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]
    finally:
        con.close()


@app.get("/")
def raiz():
    return {"servico": "FinBank — API de Consumo (Gold)", "docs": "/docs"}


@app.get("/transacoes")
def listar_transacoes(segmento: str | None = None, limit: int = 100):
    """Lista transações curadas. Filtro opcional por segmento."""
    if segmento:
        return query(
            "SELECT id_transacao, id_cliente, segmento, valor, tipo "
            "FROM main_gold.fct_transacoes WHERE segmento = ? LIMIT ?",
            [segmento, limit],
        )
    return query(
        "SELECT id_transacao, id_cliente, segmento, valor, tipo "
        "FROM main_gold.fct_transacoes LIMIT ?",
        [limit],
    )


@app.get("/clientes")
def listar_clientes(limit: int = 100):
    """Lista a dimensão de clientes (cadastro + cartão)."""
    return query("SELECT * FROM main_gold.dim_clientes LIMIT ?", [limit])


@app.get("/clientes/{id_cliente}")
def cliente_por_id(id_cliente: int):
    """Retorna um cliente e suas transações."""
    cliente = query("SELECT * FROM main_gold.dim_clientes WHERE id_cliente = ?", [id_cliente])
    if not cliente:
        raise HTTPException(status_code=404, detail="Cliente não encontrado.")
    transacoes = query(
        "SELECT id_transacao, valor, tipo FROM main_gold.fct_transacoes WHERE id_cliente = ?",
        [id_cliente],
    )
    return {"cliente": cliente[0], "transacoes": transacoes}
