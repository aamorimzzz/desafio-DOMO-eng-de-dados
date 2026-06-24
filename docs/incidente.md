# Relatório de Incidente — Receita inflada por valor sentinela

## Resumo

A Receita Total calculada sobre a base bruta apontava R$ 3,93 milhões. O número
estava errado. Uma única transação com valor R$ 999.999,00 respondia por 25,4%
desse total. Depois do tratamento, a receita correta ficou em R$ 2,88 milhões.

## O que aconteceu

Ao validar a Receita Total contra o ticket médio das transações (~R$ 2,9 mil), um
registro destoava de tudo: a transação `id_transacao = 622`, do cliente `264`, com
valor exato de R$ 999.999,00.

O padrão entrega o diagnóstico. `999999` é um número-repetição clássico usado como
placeholder ou código de erro em sistemas de origem (preenchimento default, campo
não informado, falha de parsing que grava um valor sentinela em vez de nulo). Não é
uma transação real de quase um milhão de reais.

## Por que aconteceu

O valor sentinela vazou do sistema transacional para a base analítica sem
tratamento. Origem provável: um campo obrigatório preenchido com valor default
quando o dado real estava ausente, em vez de gravar `NULL`. Como o pipeline somava
`valor` direto, o sentinela entrou na conta como receita legítima.

A base trazia ainda dois outros problemas de qualidade na tabela de transações:

- **20 transações duplicadas** (linha idêntica, mesmo `id_transacao`), sinal de
  reprocessamento ou reenvio na origem. Inflavam a receita em R$ 52.020,45 por
  dupla contagem.
- **20 transações com `valor` nulo** (após deduplicação), sem informação de valor
  para atribuir receita.

## Impacto no negócio

| Métrica | Base bruta | Após tratamento | Distorção |
|---|---|---|---|
| Receita Total | R$ 3.934.136,38 | R$ 2.882.116,93 | R$ 1.052.019,45 |
| Transações | 1.020 | 979 confiáveis | — |

A distorção de R$ 1,05 milhão se divide entre o sentinela (R$ 999.999,00) e as
cópias duplicadas (R$ 52.020,45). Um número de receita inflado em 36% alimentaria
relatórios gerenciais, metas e qualquer modelo de decisão construído sobre ele. Em
crédito, isso contamina desde a leitura de faturamento até features de modelos.

## Solução aplicada

O tratamento acontece na camada Silver, a partir do dado bruto preservado no
Bronze. Três ações:

1. **Deduplicação** por `id_transacao`, mantendo uma ocorrência.
2. **Remoção do sentinela** `999999` da base confiável.
3. **Quarentena** dos registros nulos e do próprio sentinela em
   `stg_transacoes_rejeitadas`, com o motivo da rejeição. Nada é descartado em
   silêncio: cada registro removido fica rastreável.

Decisão deliberada: os valores nulos **não** foram imputados. Preencher receita com
média ou zero seria inventar faturamento, inaceitável em contexto financeiro.

Outliers altos porém plausíveis (R$ 50 mil a R$ 250 mil) foram mantidos. São cauda
legítima de clientes PJ e alta renda, não erro. A linha que separa erro de cauda
legítima foi o padrão do valor: `999999` é sentinela, R$ 250 mil é uma transação
grande de verdade.

## Recomendações

- **Validação na ingestão**: rejeitar ou sinalizar valores sentinela conhecidos
  (`999999`, `0`, negativos onde não fazem sentido) já na entrada do Bronze.
- **Contrato de dados com a origem**: campos sem informação devem chegar como
  `NULL`, nunca como valor default que se confunde com dado real.
- **Teste de reconciliação contínuo**: o teste `assert_reconciliacao_transacoes`
  garante que toda transação da origem termina contabilizada (limpa ou em
  quarentena). Roda a cada execução do pipeline.
- **Monitorar a quarentena**: volume crescente de rejeições é sintoma de problema
  na origem, e merece alerta.
