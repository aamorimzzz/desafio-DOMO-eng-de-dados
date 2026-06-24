-- ============================================================
-- SILVER: stg_transacoes  (modelo central do desafio)
-- ------------------------------------------------------------
-- Aplica as 3 decisões de qualidade de dados:
--   1. DEDUPLICAÇÃO  -> mantém 1 ocorrência por id_transacao.
--   2. NULOS em valor -> NÃO imputados; vão p/ quarentena
--                        (stg_transacoes_rejeitadas) e são excluídos aqui.
--                        Em contexto financeiro, imputar receita = inventar
--                        dinheiro. Inaceitável.
--   3. SENTINELA 999999 -> valor placeholder/erro que vazou da origem.
--                        Removido daqui (incidente) e roteado p/ quarentena.
--                        Outliers grandes porém plausíveis (50k–250k) são
--                        MANTIDOS: cauda legítima de alto valor, não erro.
-- ============================================================

{% set sentinela_valor = 999999 %}

with bronze as (
    select * from {{ source('bronze', 'transacoes') }}
),

-- 1) Deduplicação por id_transacao (linhas idênticas reenviadas pela origem)
deduplicado as (
    select *
    from bronze
    qualify row_number() over (
        partition by id_transacao
        order by _ingested_at
    ) = 1
),

-- 2) e 3) Mantém apenas transações confiáveis: valor não-nulo e não-sentinela
limpo as (
    select *
    from deduplicado
    where valor is not null
      and valor <> {{ sentinela_valor }}
)

select
    cast(id_transacao as integer)   as id_transacao,
    cast(id_cliente as integer)     as id_cliente,
    cast(valor as double)           as valor,
    lower(trim(tipo))               as tipo,
    _ingested_at
from limpo
