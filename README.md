# MIRAVEC — pipeline de preparação

Pipeline de dados da vigilância entomológica do *Aedes aegypti* no Recife,
desenvolvido com a GEVACZ (Gerência de Vigilância Ambiental e Controle de
Zoonoses) da Prefeitura do Recife.

O pipeline lê as planilhas que a GEVACZ já preenche, trata as
inconsistências conhecidas, calcula os índices oficiais de infestação e
cruza as ovitrampas com a cobertura das Estações Disseminadoras de
Larvicida.

---

## Como executar

```bash
git clone <url-do-repositorio>
cd miravec

# 1. restaura as dependências exatas
Rscript -e 'renv::restore()'

# 2. coloque as planilhas em dados/brutos/  (ver o README de lá)

# 3. execute
Rscript executar_pipeline.R
```

Todos os caminhos do código são relativos à raiz do repositório. Não há
caminho absoluto em nenhum script: um clone limpo roda sem ajuste manual.

---

## Arquitetura em camadas

A disciplina-alvo exige tecnologias diferentes em fases diferentes. Este
repositório é a **camada de preparação**, em R/tidyverse. Ele entrega o
dado tratado em formato tidy, que alimenta as camadas seguintes.

| Camada | Tecnologia | Responsabilidade | Onde |
|---|---|---|---|
| Preparação | R / tidyverse | Ingestão, limpeza, índices, cruzamento espacial | este repositório |
| Análise exploratória | R / Quarto | Relatório de EDA | `relatorios/` |
| Visualização exploratória | Python / matplotlib, seaborn | Gráficos do MVP | repositório próprio |
| Dashboard | Ferramenta de BI | Modelo estrela e medidas | fora deste repositório |
| Entrega web | Observable Plot, Vega-Lite ou D3 | Página final | fora deste repositório |

---

## Estrutura

```
.
├── executar_pipeline.R      ponto de entrada
├── R/
│   ├── utils.R              funções de apoio e regras de coordenada
│   ├── 01_ingestao.R        leitura das três bases
│   ├── 02_indices.R         IPO, IDO e latência do processo
│   ├── 03_cobertura.R       cruzamento espacial ovitrampa × EDL
│   └── 04_diagnostico.R     relatório de qualidade e verificações
├── dados/
│   ├── brutos/              planilhas da GEVACZ (não versionadas)
│   └── tratados/            saída do pipeline (não versionada)
├── relatorios/              relatórios Quarto
├── referencia/python/       implementação de referência (opcional)
├── tests/comparar_py_r.R    confere R contra a referência
├── renv.lock                dependências exatas
├── REGISTRO-IA.md           registro de uso de IA
└── DECISOES-DE-LIMPEZA.md   cada tratamento e sua justificativa
```

---

## O que o pipeline produz

Em `dados/tratados/`:

| Arquivo | Conteúdo |
|---|---|
| `leituras_tidy.csv` | Uma linha por armadilha por ciclo, com coordenada |
| `cobertura_armadilhas.csv` | Distância até a EDL mais próxima e estado de cobertura |
| `pontos_edl.csv` | Pontos estratégicos com coordenada tratada e número de EDLs |
| `indices_ciclo_ds.csv` | IPO e IDO por ciclo e distrito |
| `indices_bairro.csv` | IPO e IDO por bairro |
| `indices_mes.csv` | Série mensal pela data real de coleta |
| `confiabilidade_ds.csv` | Quanto do parque de EDLs está visível em cada distrito |

---

## Duas coisas que o código faz de propósito

**A série temporal usa a data de coleta, não o número do ciclo.** Os ciclos
se sobrepõem muito no tempo: o ciclo 1 tem coletas de 26/01 a 25/03 e o
ciclo 4 de 10/03 a 20/05. Agrupar por ciclo e apresentar o resultado como
série temporal produz um gráfico enganoso.

**A cobertura tem três estados, não dois.** Coberta, descoberta e
desconhecida. Das 1.273 EDLs cadastradas, 473 não têm coordenada e por isso
não participam do cruzamento. Uma armadilha fora do raio de toda EDL
conhecida pode estar ao lado de uma estação que o mapa não enxerga.
Chamá-la de lacuna levaria a recomendar a instalação de uma EDL onde já
existe uma.

---

## A pasta referencia/python

Opcional. O pipeline em R não depende dela. São os scripts que perfilaram
as bases antes de o pipeline existir, mantidos como implementação de
referência: `tests/comparar_py_r.R` confere a saída do R contra a deles,
em doze métricas. Esse método já encontrou quatro defeitos que falhavam em
silêncio. Veja `referencia/python/README.md`.

---

## Documentos relacionados

- `DECISOES-DE-LIMPEZA.md` — cada tratamento aplicado e por quê
- `REGISTRO-IA.md` — uso de IA no desenvolvimento
- Dicionário de Dados — descrição variável por variável das bases
- Análise de Cobertura OVT × EDL — primeira execução do cruzamento
