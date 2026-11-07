# Decisões de limpeza

Cada tratamento que o pipeline aplica, por que ele existe e o que
aconteceria sem ele. Exigência do épico E3 do backlog: nenhuma
transformação entra no código sem justificativa registrada.

Todos os números abaixo foram medidos nas bases reais da GEVACZ.

---

## 1. Normalização do identificador da ovitrampa

**O que:** remover espaços e padronizar a caixa de `ID_OVT` antes da junção.

**Por quê:** a base de leituras grava `REC1001` e a de georreferenciamento
grava `REC 1001`. São o mesmo objeto com grafias diferentes.

**Efeito medido:**

| Junção | Armadilhas casadas |
|---|---|
| Sem normalizar | 2.501 |
| Normalizando | 2.866 |

Sem esta etapa o cruzamento perderia 365 armadilhas, 13% da base, sem
emitir erro. O pipeline reporta esse ganho a cada execução, em
`diagnosticar_juncao()`, justamente para que a regressão apareça se alguém
a remover.

**Onde:** `normalizar_id_ovt()` em `R/utils.R`.

---

## 2. Seis formatos de coordenada

**O que:** converter qualquer uma das seis representações encontradas para
grau decimal.

**Por quê:** as planilhas usam formatos diferentes, às vezes na mesma aba:

| Formato | Exemplo | Onde aparece |
|---|---|---|
| Decimal correto | `-8.059653` | DS 4, parte do DS 1 |
| Inteiro sem separador | `-8067246`, `80137209` | vários |
| Grau, minuto e segundo | `8º4'52.59"S` | DS 6 |
| Par numa célula só | `-7.9942062, -34.8967671` | DS 3 |
| Espaço como separador | `8 0803258` | DS 5 |
| Espaço depois do ponto | `8. 0194858` | georreferenciamento do DS II |

**A armadilha técnica:** no formato inteiro, a escala **varia de linha para
linha dentro do mesmo arquivo**, de 6 a 8 dígitos. Dividir tudo por um
fator fixo, que era o plano inicial, corromperia parte dos dados. A regra
correta escolhe a posição do separador por qual resultado cai na magnitude
esperada: 8 graus para latitude, 34 para longitude.

**Efeito medido:** coordenadas de pontos estratégicos recuperáveis passam
de 56 para 187. O sexto formato, sozinho, recuperou 3.036 leituras do
DS II, que antes ficavam todas sem coordenada.

**Onde:** `ler_coordenada()` e `ler_par_coord()` em `R/utils.R`.

---

## 3. Reaplicação do sinal

**O que:** descartar o sinal lido e forçar latitude e longitude negativas.

**Por quê:** o sinal é gravado de forma inconsistente entre distritos. Há
latitude positiva onde deveria ser negativa, e vice-versa.

**Por que é seguro:** o município do Recife cabe inteiro no quadrante
sul-oeste, entre as latitudes −8,30 e −7,90 e as longitudes −35,05 e
−34,80. Não existe ponto válido com sinal positivo.

**Limite da regra:** ela vale para este município. Se o projeto for
estendido a outra cidade, a regra precisa ser revista.

**Onde:** `para_sul_oeste()` em `R/utils.R`.

---

## 4. Coordenada fora do município vira ausente

**O que:** zerar o par quando ele cai fora dos limites do Recife.

**Por quê:** coordenada fora do município é erro de origem, não de
leitura. Cerca de 2.000 leituras do DS II têm longitude próxima de −34,53,
que cai no oceano.

**Decisão:** marcar como ausente, não tentar corrigir. Um ponto plotado no
mar é pior do que um ponto faltando, porque parece dado válido.

**Onde:** `validar_no_recife()` em `R/utils.R`.

---

## 5. Detecção do cabeçalho por conteúdo

**O que:** procurar a linha do cabeçalho pelas palavras-chave do domínio em
vez de assumir posição fixa.

**Por quê:** a posição varia de 0 a 12 entre os arquivos:

| Arquivo | Linha do cabeçalho |
|---|---|
| Leituras | 0 |
| Georreferenciamento | 2 |
| Pontos estratégicos | 4 |
| Arquivos distritais avulsos | 0, 8, 10 ou 12 |

**Onde:** `achar_cabecalho()` em `R/utils.R`.

---

## 6. Denominador do IPO

**O que:** considerar examinada a armadilha com contagem numérica de ovos;
armadilhas marcadas como fechada (`F`), extraviada (`E`), recusada (`R`) ou
desocupada (`D`) ficam fora do denominador.

**Status: pendente de confirmação da GEVACZ.**

**Por que isso importa:** com esta regra o IPO fica entre 97,0% e 99,5% em
todos os ciclos e todos os distritos. Um índice que não varia não
discrimina território nem período, e portanto não orienta decisão. Ou o
denominador está errado, ou a positividade no Recife está saturada e o IPO
perdeu poder informativo.

**Consequência prática:** enquanto a confirmação não vem, **o IDO é o
índice que o projeto usa para decisão**, e o IPO entra como contexto.

**Onde:** `OBS_SEM_LEITURA` e `classificar_leituras()` em `R/02_indices.R`.

---

## 7. Série temporal pela data de coleta

**O que:** agrupar a série por mês de `dt_coleta`, não pelo número do ciclo.

**Por quê:** os ciclos se sobrepõem muito no tempo.

| Ciclo | Primeira coleta | Última coleta |
|---|---|---|
| 1 | 26/01 | 25/03 |
| 4 | 10/03 | 20/05 |
| 8 | 27/04 | 13/07 |

O rótulo do ciclo é administrativo e não delimita uma janela temporal.
Tratá-lo como eixo do tempo produz um gráfico que parece uma série e não é.

**Onde:** `serie_mensal()` em `R/02_indices.R`.

---

## 8. Raio de cobertura de 500 metros

**O que:** uma armadilha é coberta quando há ponto estratégico com EDL
dentro de 500 m.

**De onde vem o número:** a GEVACZ calcula a distância média entre estações
por distrito, e ela varia de 458 a 769 m. O padrão fica no meio dessa
faixa.

**Status: pendente de confirmação.** O valor é uma escolha do grupo a
partir da prática observada, não um raio de ação técnico do larvicida. A
pergunta está registrada no dicionário de dados.

**Mitigação:** o parâmetro é uma constante única, `RAIO_PADRAO_M`, para que
a sensibilidade do resultado ao raio possa ser testada em uma linha.

**Onde:** `R/03_cobertura.R`.

---

## 9. Cobertura com três estados

**O que:** classificar cada armadilha em coberta, descoberta ou
**desconhecida**, em vez de apenas coberta e descoberta.

**Por quê:** 473 das 1.273 EDLs cadastradas não têm coordenada e não
participam do cruzamento. A correlação entre a cobertura aparente de um
distrito e a completude das suas coordenadas é **r = 0,78**: o mapa mede,
em boa parte, a qualidade do cadastro e não a cobertura real.

| Distrito | EDLs sem coordenada |
|---|---|
| III | 198 |
| IV | 102 |
| II | 43 |
| VI | 39 |
| V | 34 |
| VII | 29 |
| VIII | 28 |
| I | 0 |

**Regra:** fora do raio, o estado só é "descoberta" se o distrito tiver
todas as suas EDLs georreferenciadas. Caso contrário é "desconhecida".

**O erro que isso evita:** recomendar a instalação de uma EDL onde já
existe uma, que é exatamente o que o projeto se propõe a evitar.

**Onde:** `classificar_cobertura()` em `R/03_cobertura.R`.

---

## 10. Pontos estratégicos sem EDL não cobrem nada

**O que:** só entram no cruzamento os pontos com `QUANT. DE EDL REAL`
maior que zero.

**Por quê:** ponto estratégico e estação disseminadora não são a mesma
coisa. O PE é um imóvel de risco cadastrado; a EDL é o equipamento
instalado nele. No arquivo distrital do DS IV, apenas 8 de 85 pontos têm
estação.

**Onde:** `distancia_ate_edl()` em `R/03_cobertura.R`.

---

## 11. Inferência de tipo do readxl

**O que:** ler todas as planilhas com `guess_max = 1e5` em vez do padrão.

**Por quê:** o `readxl` decide o tipo de cada coluna olhando as primeiras
1.000 linhas. Em `DT_ENVIO_DS`, a primeira célula preenchida é a **linha
17.767**. Com o padrão, a coluna inteira é tipada como `logical` e os
13.687 valores são descartados — sem erro, sem aviso.

**Como foi detectado:** o diagnóstico da primeira execução em R reportou
0 registros com data de envio ao distrito, contra 43,5% na implementação
de referência em Python. O `pandas` lê a coluna inteira e não tem esse
atalho, então a divergência entre as duas implementações expôs o
problema.

**Efeito medido:** 13.687 datas recuperadas, e a métrica de latência
"coleta → envio ao distrito" passou de inexistente a calculável.

**Por que isso vale registro:** é uma perda silenciosa de dado. Um
pipeline que rodasse só em R, sem a comparação, teria reportado que o
campo está vazio — e a conclusão seria sobre a GEVACZ, não sobre a
biblioteca.

**Onde:** `LINHAS_PARA_INFERIR_TIPO` em `R/01_ingestao.R`.

---

## 12. Conversão de datas tolerante a falha e a tipos mistos

**O que:** converter cada coluna de data aplicando três estratégias em
sequência — serial do Excel, formatos escritos, descarte do implausível —
em vez de escolher uma.

**Por quê, em três camadas:**

`as.Date` com `tryFormats` **interrompe a execução** quando nenhum formato
casa, em vez de devolver `NA`. Uma única célula mal formatada derruba o
pipeline inteiro.

Uma coluna pode vir como texto contendo o **serial do Excel**. É o caso de
`DT_DIG`: 30.461 valores como `"46088"` e **uma única** data escrita à
mão. Basta essa célula destoante para o `readxl` tipar a coluna inteira
como texto, e aí o serial deixa de ser reconhecido como data.

A célula destoante é `"14/06/20260"` — ano com cinco dígitos. Interpretada
literalmente, produz uma data no ano 20260 e um valor de latência absurdo.
Por isso toda data convertida passa por uma faixa de plausibilidade, de
2015 a 2035.

**Efeito medido:** a latência "leitura → digitação" passou de 1 registro
para 30.445, e "coleta → digitação" de 1 para 30.459.

**Como foi detectado:** pela execução em outra máquina. O pipeline rodou
no Windows com `readxl` 1.6.0 e a tabela de latência mostrou `n = 1` em
duas etapas. A mesma falha estava no ambiente de desenvolvimento e passou
despercebida porque o teste de comparação entre R e Python só cobria as
métricas de cobertura, não as de latência. O teste foi ampliado.

**Onde:** `como_data()` e `plausivel_ou_na()` em `R/utils.R`.

---

## 13. Arquivos duplicados

**O que:** quando mais de um arquivo casa com o padrão de busca, o pipeline
usa o primeiro e **emite aviso**.

**Por quê:** cada `Planilha OVT DS*.xls` aparece duas vezes no acervo, com
tamanhos diferentes, e não há critério no nome que indique a versão
vigente.

**Status:** pendente. A pergunta está no dicionário de dados. O aviso
existe para que a ambiguidade não passe despercebida.

**Onde:** `localizar()` em `R/01_ingestao.R`.
