-- ============================================================
-- TESTE SINGULAR: reconciliação de transações
-- ------------------------------------------------------------
-- Garante que NENHUMA transação foi perdida silenciosamente no
-- pipeline. A conta tem que fechar:
--
--   transações limpas (Silver) + quarentena = id_transacao
--   distintos na origem (Bronze, após deduplicação).
--
-- Um teste dbt singular FALHA se a query retorna alguma linha.
-- Aqui retornamos linha apenas quando os totais não batem.
-- Esse tipo de reconciliação é padrão em pipelines financeiros:
-- toda entrada precisa ser rastreável até a saída.
-- ============================================================

with origem as (
    select count(distinct id_transacao) as n_origem
    from {{ source('bronze', 'transacoes') }}
),
processado as (
    select
        (select count(*) from {{ ref('stg_transacoes') }})
      + (select count(*) from {{ ref('stg_transacoes_rejeitadas') }}) as n_processado
)

select
    origem.n_origem,
    processado.n_processado
from origem, processado
where origem.n_origem <> processado.n_processado
