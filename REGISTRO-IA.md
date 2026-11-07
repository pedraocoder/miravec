# Registro de uso de IA

Exigência da disciplina de Análise e Visualização de Dados. Cada entrada
diz o que foi gerado com apoio de IA, com qual ferramenta, e **como o
resultado foi verificado** — a verificação é a parte que importa.

Ferramenta usada: Claude (Anthropic).

---

## 2026-10-27 — Perfilamento das bases

**O que:** scripts em Python para ler as planilhas da GEVACZ e levantar
estrutura, volumes, tipos e anomalias.

**Verificação:** todos os números do perfilamento foram conferidos contra
a leitura direta dos arquivos. Três erros foram encontrados e corrigidos
durante o processo:

1. A primeira versão do parser de coordenadas assumia escala fixa e
   derrubava DS 3 e DS 5. Detectado porque os dois distritos retornaram
   zero coordenadas válidas, o que era implausível.
2. A segunda versão não tratava sinal invertido e derrubava DS 7 e DS 8.
   Detectado pelo mesmo sintoma.
3. A terceira não tratava graus-minutos-segundos e derrubava DS 6.

O padrão de verificação adotado a partir daí: **resultado zero em um
distrito inteiro é tratado como suspeita de bug, não como achado**, até
inspeção manual do arquivo.

---

## 2026-10-27 — Dicionário de dados

**O que:** redação do documento a partir do perfilamento.

**Verificação:** cada número citado no dicionário foi extraído por script,
não digitado à mão. Os domínios de `OBS` e as fórmulas de IPO e IDO foram
conferidos contra o material de treinamento da própria GEVACZ.

---

## 2026-10-27 — Cruzamento espacial

**O que:** implementação em Python do cálculo de distância e da
classificação de cobertura.

**Verificação:** a execução revelou um sexto formato de coordenada que o
dicionário não havia catalogado (`8. 0194858`, no DS II). Isso foi
detectado porque o distrito aparecia com zero armadilhas georreferenciadas
apesar de ter 420 linhas na aba de georreferenciamento — novamente o
padrão "zero é suspeito".

Também foi testada a hipótese de que a cobertura aparente seria artefato
da completude das coordenadas. A correlação medida, r = 0,78, confirmou a
suspeita e levou à criação do terceiro estado de cobertura.

---

## 2026-11-06 — Pipeline em R

**O que:** tradução para R/tidyverse da lógica validada em Python, mais a
estrutura do repositório.

**Verificação:** o pipeline foi executado sobre as bases reais e sua saída
comparada com a da implementação em Python, por `tests/comparar_py_r.R`.
Resultado da comparação:

| Métrica | R | Python |
|---|---|---|
| Armadilhas georreferenciadas | 2.653 | 2.653 |
| Distância mediana até a EDL | 471 m | 471 m |
| Cobertas a 500 m | 1.418 | 1.418 |
| Distância máxima | 11.379 m | 11.379 m |

**Três defeitos foram encontrados pela comparação, não pela leitura do
código:**

1. `DT_ENVIO_DS` vinha vazia em R e preenchida em Python. Causa: o
   `readxl` infere tipo pelas primeiras 1.000 linhas e a primeira célula
   preenchida é a 17.767. Perda silenciosa de 13.687 valores.
2. `as.Date` com `tryFormats` interrompia a execução em vez de devolver
   `NA` quando nenhum formato casava.
3. O diagnóstico do ganho da normalização da chave media uma simulação do
   identificador, não o identificador real, e reportava zero. Passou a
   guardar a forma crua de ambos os arquivos.

**O que isso reforça:** manter duas implementações independentes da mesma
lógica é o que torna esse tipo de defeito visível. Nenhum dos três
apareceria em uma revisão de código, porque todos falham em silêncio.

---

## 2026-11-06 — Quarto defeito, encontrado na execução em outra máquina

**O que:** ao rodar o pipeline no Windows com `readxl` 1.6.0, a tabela de
latência mostrou `n = 1` em duas das quatro etapas.

**Causa:** `DT_DIG` chega como texto contendo o serial do Excel
(`"46088"`), porque uma única célula da coluna tem uma data escrita à mão
com erro de digitação (`"14/06/20260"`). Essa célula faz o `readxl` tipar
a coluna inteira como texto, e o conversor de datas, que tratava serial
numérico mas não serial em texto, devolvia `NA` para 30.461 valores.

**O que falhou na verificação:** o defeito estava também no ambiente de
desenvolvimento, e passou. O teste `comparar_py_r.R` comparava apenas as
métricas de cobertura; as de latência não eram verificadas. O relatório
de execução mostrava `n = 1` na tela e isso não foi conferido antes da
entrega.

**Correção dupla:** a função `como_data()` passou a aplicar serial,
formatos escritos e faixa de plausibilidade em sequência, em vez de
escolher uma estratégia. E o teste de comparação passou a cobrir as
quatro métricas de latência, em contagem e mediana.

**Lição registrada:** uma tabela impressa no relatório de execução não é
verificação. O que não está no teste automatizado não está verificado.

---

## Como este registro é mantido

Uma entrada por bloco de trabalho, no dia em que ocorre. Entradas não são
reescritas depois: uma correção vira entrada nova.
