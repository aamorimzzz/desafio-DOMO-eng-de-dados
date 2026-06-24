-- ============================================================
-- GOLD: fct_transacoes
-- ------------------------------------------------------------
-- Camada de consumo: tabela-fato de transações curadas, prontas
-- para uso downstream. Parte das transações confiáveis (Silver) e
-- enriquece com o segmento do cliente, evitando que o consumidor
-- precise refazer o join. Grão de transação, sem agregação.
-- ============================================================

with transacoes as (
    select * from {{ ref('stg_transacoes') }}
),
clientes as (
    select id_cliente, segmento from {{ ref('stg_clientes') }}
)

select
    t.id_transacao,
    t.id_cliente,
    c.segmento,
    t.valor,
    t.tipo
from transacoes t
left join clientes c using (id_cliente)
