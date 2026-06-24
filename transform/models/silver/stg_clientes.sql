-- ============================================================
-- SILVER: stg_clientes
-- ------------------------------------------------------------
-- Camada Silver = dado limpo e conformado.
-- A tabela clientes do Bronze já chega íntegra (sem nulos/dups),
-- então aqui apenas padronizamos e tipamos explicitamente.
-- Padronização de 'segmento' (lower/trim) garante consistência mesmo
-- que a origem mude no futuro — robustez defensiva.
-- ============================================================

with bronze as (
    select * from {{ source('bronze', 'clientes') }}
)

select
    cast(id_cliente as integer)              as id_cliente,
    lower(trim(segmento))                    as segmento,
    cast(score_credito as integer)           as score_credito,
    _ingested_at
from bronze
