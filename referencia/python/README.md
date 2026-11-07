# Implementação de referência em Python

**Você não precisa destes scripts para usar o projeto.** O pipeline em R é
autossuficiente: `Rscript executar_pipeline.R` lê as planilhas e produz
tudo.

Estes arquivos existem por dois motivos.

## 1. Foram a investigação que veio antes do pipeline

Antes de escrever uma linha de R, as bases da GEVACZ foram perfiladas em
Python. Foi assim que o projeto descobriu:

- os seis formatos distintos de coordenada nas planilhas;
- que a chave de junção estava quebrada por um espaço (`REC1001` contra
  `REC 1001`), o que custava 365 armadilhas em silêncio;
- que o IPO fica saturado entre 97% e 99,5% e não discrimina nada;
- que a cobertura aparente acompanha a completude das coordenadas, com
  correlação de 0,78.

Esses achados viraram o dicionário de dados e as decisões de limpeza que
o pipeline em R implementa.

## 2. São a referência contra a qual o pipeline em R é verificado

Duas implementações independentes da mesma lógica, escritas em linguagens
diferentes, devem chegar ao mesmo número. Quando não chegam, há um defeito
em alguma delas.

Esse método já encontrou quatro defeitos que **nenhuma revisão de código
teria pego**, porque todos falhavam em silêncio:

| Defeito | Efeito |
|---|---|
| `readxl` infere tipo pelas primeiras mil linhas | 13.687 datas descartadas sem erro |
| `as.Date` com `tryFormats` interrompe a execução | pipeline derrubado por uma célula |
| Serial do Excel lido como texto em `DT_DIG` | 30.459 registros de latência perdidos |
| Diagnóstico media uma simulação da chave | ganho da normalização reportado como zero |

## Como executar

A partir da raiz do repositório, com as planilhas em `dados/brutos/`:

```bash
pip install pandas openpyxl numpy
python referencia/python/constroi_base.py
python referencia/python/analise_cobertura.py
```

A saída vai para `dados/tratados_py/`, separada da saída do R justamente
para que as duas possam ser comparadas.

Depois:

```bash
Rscript tests/comparar_py_r.R
```

O teste confere doze métricas: quatro de cobertura e oito de latência, em
contagem e mediana. Qualquer divergência é tratada como erro até ser
explicada.

## O que estes scripts não são

Eles **não** atendem o épico E5 do backlog, que pede gráficos em
`matplotlib` e `seaborn`. Aqui não se desenha nada: é preparação e
cálculo, igual ao pipeline em R. A visualização em Python é trabalho
ainda por fazer.
