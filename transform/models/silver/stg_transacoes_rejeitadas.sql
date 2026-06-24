-- ============================================================
-- SILVER: stg_transacoes_rejeitadas  (quarentena)
-- ------------------------------------------------------------
-- Em vez de descartar silenciosamente as transações problemáticas,
-- nós as ISOLAMOS com o motivo da rejeição. Isso permite:
--   - auditoria (quem rejeitou o quê e por quê);
--   - investigação posterior pela origem;
--   - quantificação do impacto (quanto de dado foi perdido).
-- Padrão "dead-letter / quarantine table" — esperado em pipelines
-- de dados regulados.
-- ============================================================

{% set sentinela_valor = 999999 %}

with bronze as (
    select * from {{ source('bronze', 'transacoes') }}
),

-- Mesma deduplicação aplicada na trilha limpa, p/ não duplicar rejeições
deduplicado as (
    select *
    from bronze
    qualify row_number() over (
        partition by id_transacao
        order by _ingested_at
    ) = 1
)

select
    cast(id_transacao as integer)   as id_transacao,
    cast(id_cliente as integer)     as id_cliente,
    valor,
    lower(trim(tipo))               as tipo,
    case
        when valor is null                  then 'valor_nulo'
        when valor = {{ sentinela_valor }}  then 'valor_sentinela_999999'
    end                              as motivo_rejeicao,
    _ingested_at
from deduplicado
where valor is null
   or valor = {{ sentinela_valor }}
