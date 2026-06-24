# Desafio de Engenharia de Dados — Domo Inovação

> Dataset do desafio: **FinBank** (base fictícia de transações financeiras em xlsx).

Pipeline de dados financeiro em arquitetura medallion (Bronze, Silver, Gold), com
ingestão em Python, transformação e testes de qualidade em dbt sobre DuckDB, e uma
API para consumo dos dados curados.

## Visão Geral

O desafio entrega uma base de transações financeiras "suja" e pede um pipeline que
a transforme em dados confiáveis para análise, identificando e tratando os
problemas de qualidade pelo caminho.

A base tem três tabelas: `clientes` (segmento e score de crédito), `transacoes`
(movimentações) e `cartao` (fatura e dias de atraso). A tabela de transações
concentra os problemas: duplicatas, valores nulos e um valor sentinela que inflava
a receita em 36%. O [relatório de incidente](docs/incidente.md) detalha a
investigação.

O resultado é uma camada Gold curada e pronta para consumo: uma tabela-fato de
transações enriquecidas com o segmento do cliente e uma dimensão de clientes
consolidada.

## Arquitetura

O pipeline segue o padrão medallion, com cada camada cumprindo um papel:

```
  desafio_dados_finbank_dirty.xlsx
        │
        ▼
   [ ingestão Python ]
        │
        ▼
   BRONZE   raw imutável, sem tratamento (schema bronze no DuckDB)
        │
        ▼
   SILVER   limpo e conformado: dedup, quarentena de nulos, remoção do sentinela
        │
        ▼
   GOLD     camada de consumo: transações curadas + dimensão de clientes
```

**Bronze** guarda o dado como veio da origem, sem limpeza. Esse princípio garante
rastreabilidade: se a regra de tratamento mudar, a Silver é reconstruída a partir
do Bronze sem reextrair a origem.

**Silver** aplica as decisões de qualidade. Transações confiáveis seguem para
`stg_transacoes`; registros problemáticos vão para a quarentena
`stg_transacoes_rejeitadas`, com o motivo da rejeição.

**Gold** materializa a camada de consumo: uma tabela-fato de transações
enriquecidas e a dimensão de clientes, prontas para uso downstream.

O dbt resolve sozinho o grafo de dependências das transformações: as referências
`ref()` e `source()` declaram que Silver lê do Bronze e Gold lê da Silver, e o dbt
executa os modelos na ordem correta. A ingestão (Python) roda antes, alimentando o
Bronze; em seguida `dbt build` materializa Silver e Gold e roda os testes.

### de dev para produção

Usei DuckDB e dbt porque a base é pequena (~1,6 mil linhas) e assim o projeto roda em qualquer máquina, sem complicação. Num cenário real, com volume grande, a mesma arquitetura seria feita em PySpark ou mysql e Delta Lake no Databricks — a ideia das camadas e os testes continuam iguais, só muda a ferramenta:

| DEv (versão de teste local) | Em produção |
|---|---|
| Ingestão com pandas no DuckDB | Job em PySpark gravando em Delta (Bronze) |
| Transformações em dbt no DuckDB | dbt ou PySpark gravando em Delta (Silver/Gold) |
| Tabela DuckDB | Tabela Delta (com histórico e atualização incremental) |
| Rodar na mão (ingest + dbt build) | Agendamento automático (Databricks Workflows ou Azure Data Factory) |

Ou seja, o que está aqui é a mesma lógica que rodaria em produção, só numa escala menor e mais simples de executar.
### Observação — escopo e ambiente híbrido

O enunciado descreve um cenário de pipeline em **ambiente híbrido on-premises +
cloud**. Numa implementação real, os dados transacionais nasceriam on-premises (por
exemplo, o core bancário) e seriam ingeridos para uma zona cloud (data lake), onde
o tratamento medallion (Bronze, Silver, Gold) rodaria na nuvem. O padrão de camadas
e a lógica de qualidade aqui aplicados são os mesmos, independente da origem ser
on-premises ou cloud.

Para este teste, o pipeline foi construído **considerando apenas a base de dados
fornecida** (`finbank_dirty.xlsx`). A camada de extração on-premises e a movimentação
para a cloud não foram implementadas, por estarem fora do material da base disponibilizado em xlsx.

## Como Executar

### Pré-requisitos

- Python 3.10+
- `pip install -r requirements.txt`

### Execução

Dois passos rodam a ingestão, as transformações e os testes:

```bash
# 1. Ingestão: xlsx -> Bronze
python ingestion/ingest.py

# 2. Transformações + testes: Bronze para Silver para Gold
cd transform
DBT_PROFILES_DIR=. dbt build
```

Ao final, o banco `transform/finbank.duckdb` contém os schemas `bronze`,
`main_silver` e `main_gold`.


### API de consumo

A API expõe os dados curados da camada Gold via HTTP (transações e clientes). Para subir localmente:

```bash
uvicorn api.main:app --reload
# documentação interativa em http://localhost:8000/docs
```

Com a API no ar, a documentação interativa fica em `http://localhost:8000/docs`, onde dá pra testar os endpoints direto pelo navegador.

## Pipeline de Dados

### Estrutura do repositório

```
/data/raw/        base de origem (raw)
/ingestion/       carga para o Bronze (ingest.py)
/transform/       projeto dbt
   ├─ models/     modelos Silver e Gold + fontes (sources.yml)
   └─ tests/      teste singular de reconciliação
/api/             API que expõe os dados da Gold
/docs/            relatório de incidente
README.md
```

> Os testes de qualidade vivem dentro do projeto dbt, seguindo a convenção da
> ferramenta: testes genéricos declarados nos `schema.yml` e o teste singular de
> reconciliação em `transform/tests/`.

### Modelos dbt

| Camada | Modelo | Papel |
|---|---|---|
| Silver | `stg_clientes` | clientes limpos e padronizados |
| Silver | `stg_cartao` | faturas de cartão |
| Silver | `stg_transacoes` | transações confiáveis (deduplicadas, sem nulo, sem sentinela) |
| Silver | `stg_transacoes_rejeitadas` | quarentena com motivo da rejeição |
| Gold | `fct_transacoes` | tabela-fato de transações curadas, enriquecidas com segmento |
| Gold | `dim_clientes` | dimensão de clientes (cadastro + cartão) |

### Testes de qualidade

O pipeline roda 37 verificações a cada `dbt build`:

- **not_null / unique** nas chaves (`id_cliente`, `id_transacao`).
- **accepted_values** nos domínios (`segmento`, `tipo`, `dias_atraso`).
- **relationships** para integridade referencial (toda transação e todo cartão
  apontam para um cliente existente).
- **reconciliação** (teste singular): limpas + quarentena = transações distintas na
  origem. Garante que nenhum registro some em silêncio.

## Incidente Identificado

O faturamento bruto somado da base (R$ 3,93 milhões) estava inflado por uma
transação com valor R$ 999.999,00 (`id_transacao = 622`), um valor sentinela vazado
da origem que respondia por 25,4% do total. Somavam-se 20 transações duplicadas
(R$ 52 mil em dupla contagem) e 20 com valor nulo.

Investigação completa, impacto e recomendações em [docs/incidente.md](docs/incidente.md).

## Solução Aplicada

Tratamento na camada Silver, preservando o Bronze intacto:

1. **Deduplicação** por `id_transacao`.
2. **Remoção do sentinela** `999999` da base confiável.
3. **Quarentena** de nulos e sentinela em `stg_transacoes_rejeitadas`, com motivo.

Decisões registradas: valores nulos não foram imputados (imputar receita é inventar
faturamento). Outliers plausíveis (R$ 50 mil a R$ 250 mil) foram mantidos como cauda
legítima. O teste de reconciliação confirma que toda transação da origem termina
contabilizada, limpa ou em quarentena.

Receita corrigida: **R$ 2,88 milhões**.
