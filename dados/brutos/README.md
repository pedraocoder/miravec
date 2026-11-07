# dados/brutos

As planilhas da GEVACZ **não são versionadas**. Coloque-as aqui antes de
executar o pipeline.

## Arquivos esperados

| Arquivo | Padrão de busca | Conteúdo |
|---|---|---|
| Planilha geral de ovitrampas 2026 | `PLANILHA.*GERAL.*OVT.*\.xlsx` | 31.455 leituras, 12 ciclos |
| Georreferenciamento OVT 2026 | `GEORREFERENCIAMENTO.*OVT.*\.xlsx` | 2.871 armadilhas, 8 abas |
| Total de EDL por DS | `TOTAL.*EDL.*POR.*DS.*\.xlsx` | 351 pontos, 1.273 EDLs |

O pipeline localiza cada arquivo pelo padrão, não pelo nome exato: os
nomes originais têm acentos e espaçamento irregular, e mudam entre
versões. Não é preciso renomear nada.

## Se houver cópias duplicadas

O acervo entregue pela GEVACZ contém cópias do mesmo arquivo com tamanhos
diferentes. Quando mais de um arquivo casa com o padrão, o pipeline usa o
primeiro e emite aviso. Deixe aqui apenas a versão vigente.
