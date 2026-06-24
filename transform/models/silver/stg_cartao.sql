-- ============================================================
-- SILVER: stg_cartao
-- ------------------------------------------------------------
-- Faturas de cartão por cliente. Bronze chega íntegro
-- (sem nulos/dups, dias_atraso em domínio conhecido).
-- Tipagem explícita e nada mais — não inventamos tratamento
-- onde não há problema (isso também é decisão consciente).
-- ============================================================

with bronze as (
    select * from {{ source('bronze', 'cartao') }}
)

select
    cast(id_cliente as integer)      as id_cliente,
    cast(valor_fatura as double)     as valor_fatura,
    cast(dias_atraso as integer)     as dias_atraso,
    _ingested_at
from bronze
