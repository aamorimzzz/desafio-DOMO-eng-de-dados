-- ============================================================
-- GOLD: dim_clientes
-- ------------------------------------------------------------
-- Camada de consumo: dimensão de clientes, consolidando os
-- atributos cadastrais (segmento, score) com os dados de cartão
-- (fatura, dias de atraso) num único registro por cliente.
-- Modelagem dimensional, sem cálculo de indicadores.
-- ============================================================

with clientes as (
    select * from {{ ref('stg_clientes') }}
),
cartao as (
    select * from {{ ref('stg_cartao') }}
)

select
    c.id_cliente,
    c.segmento,
    c.score_credito,
    ca.valor_fatura,
    ca.dias_atraso
from clientes c
left join cartao ca using (id_cliente)
