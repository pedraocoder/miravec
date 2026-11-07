# 03_cobertura.R --------------------------------------------------------
# Cruzamento espacial entre ovitrampas e estacoes disseminadoras.
#
# Nao existe chave comum entre as bases: a juncao e por distancia. Uma
# armadilha e considerada coberta quando ha ao menos um ponto estrategico
# com EDL instalada dentro do raio de referencia.

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(tidyr)
})

# A GEVACZ calcula a distancia media entre estacoes por distrito, de 458 a
# 769 m. O raio padrao fica no meio dessa faixa.
#
# PENDENTE DE CONFIRMACAO: existe um raio de acao tecnico do larvicida que
# a GEVACZ utilize? Ver pergunta 5 do dicionario de dados.
RAIO_PADRAO_M <- 500


#' Distancia de cada armadilha ate a EDL mais proxima.
#'
#' Considera apenas pontos que tem coordenada E ao menos uma EDL
#' instalada: um ponto estrategico sem estacao nao cobre nada.
distancia_ate_edl <- function(armadilhas, pontos_edl) {
  fontes <- pontos_edl |>
    filter(!is.na(lat), !is.na(lon), !is.na(qt_edl), qt_edl > 0)

  if (nrow(fontes) == 0) {
    stop("Nenhum ponto estrategico com EDL e coordenada.", call. = FALSE)
  }

  armadilhas |>
    filter(!is.na(lat), !is.na(lon)) |>
    mutate(
      dists = map2(lat, lon, ~ distancia_m(.x, .y, fontes$lat, fontes$lon)),
      dist_edl_m = map_dbl(dists, min),
      edl_proxima = map_chr(
        dists, ~ as.character(fontes$nome_pe[which.min(.x)])
      ),
      edls_no_raio = map_dbl(
        dists, ~ sum(fontes$qt_edl[.x <= RAIO_PADRAO_M], na.rm = TRUE)
      )
    ) |>
    select(-dists)
}


#' Quanto do parque de EDLs esta visivel em cada distrito.
#'
#' Uma EDL sem coordenada nao participa do cruzamento. Como ela existe no
#' territorio mas nao no mapa, a area em volta aparece descoberta sem
#' estar. Esta tabela e o que separa "descoberta" de "nao sabemos".
confiabilidade_por_ds <- function(pontos_edl) {
  pontos_edl |>
    group_by(ds) |>
    summarise(
      pe_total     = n(),
      pe_com_coord = sum(!is.na(lat)),
      edl_total    = sum(qt_edl, na.rm = TRUE),
      edl_visivel  = sum(qt_edl[!is.na(lat)], na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(
      edl_oculta  = edl_total - edl_visivel,
      pct_visivel = round(100 * edl_visivel / edl_total, 1)
    )
}


#' Classifica cada armadilha em coberta, descoberta ou desconhecida.
#'
#' O terceiro estado e obrigatorio. Com 473 das 1.273 EDLs sem coordenada,
#' uma armadilha fora do raio de toda EDL conhecida pode estar, na
#' pratica, ao lado de uma estacao que o mapa nao enxerga. Chamar isso de
#' lacuna levaria a recomendar a instalacao de uma EDL onde ja existe uma,
#' que e exatamente o erro que o projeto se propoe a evitar.
#'
#' Regra: fora do raio, o estado so e "descoberta" se o distrito tiver
#' todas as suas EDLs georreferenciadas. Caso contrario e "desconhecida".
classificar_cobertura <- function(armadilhas_com_dist, confianca,
                                  raio_m = RAIO_PADRAO_M) {
  armadilhas_com_dist |>
    left_join(select(confianca, ds, edl_oculta), by = "ds") |>
    mutate(
      cobertura = case_when(
        dist_edl_m <= raio_m          ~ "coberta",
        edl_oculta > 0                ~ "desconhecida",
        TRUE                          ~ "descoberta"
      )
    )
}


#' Cobertura agregada por distrito.
resumo_cobertura <- function(armadilhas_classificadas) {
  armadilhas_classificadas |>
    count(ds, cobertura) |>
    pivot_wider(
      names_from = cobertura, values_from = n, values_fill = 0
    ) |>
    rowwise() |>
    mutate(armadilhas = sum(c_across(-ds))) |>
    ungroup()
}


#' Bairros candidatos a lacuna de cobertura.
#'
#' Candidatos, nao lacunas confirmadas: um bairro so e lacuna confirmada
#' se nenhuma de suas armadilhas estiver classificada como desconhecida.
candidatos_a_lacuna <- function(armadilhas_classificadas, indices_bairro,
                                min_leituras = 50) {
  por_bairro <- armadilhas_classificadas |>
    group_by(bairro) |>
    summarise(
      armadilhas   = n(),
      cobertas     = sum(cobertura == "coberta"),
      desconhecidas = sum(cobertura == "desconhecida"),
      .groups = "drop"
    ) |>
    mutate(pct_coberta = round(100 * cobertas / armadilhas, 1))

  indices_bairro |>
    filter(examinadas >= min_leituras) |>
    inner_join(por_bairro, by = "bairro") |>
    filter(cobertas == 0) |>
    mutate(
      situacao = if_else(
        desconhecidas == 0, "lacuna confirmada", "candidato, dado incompleto"
      )
    ) |>
    arrange(desc(ido)) |>
    select(bairro, examinadas, ipo, ido, armadilhas, situacao)
}
