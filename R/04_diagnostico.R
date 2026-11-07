# 04_diagnostico.R ------------------------------------------------------
# Relatorio de qualidade do dado, emitido a cada execucao.
#
# O pipeline nao deve falhar em silencio nem passar adiante um numero que
# parece solido e nao e. Cada execucao reporta quanto do dado sobreviveu a
# cada etapa e quais verificacoes passaram.

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
})


#' Diagnostico da base de leituras.
diagnosticar_leituras <- function(leituras) {
  total <- nrow(leituras)
  tibble::tibble(
    item = c(
      "linhas",
      "ciclos distintos",
      "distritos",
      "bairros",
      "armadilhas distintas",
      "com contagem de ovos",
      "com data de coleta",
      "com data de envio ao distrito",
      "sem contagem de ovos"
    ),
    valor = c(
      total,
      n_distinct(leituras$ciclo),
      n_distinct(leituras$ds),
      n_distinct(leituras$bairro),
      n_distinct(leituras$id_ovt),
      sum(!is.na(leituras$n_ovos)),
      sum(!is.na(leituras$dt_coleta)),
      sum(!is.na(leituras$dt_envio_ds)),
      sum(is.na(leituras$n_ovos))
    )
  ) |>
    mutate(pct = round(100 * valor / total, 1))
}


#' Diagnostico da juncao entre leituras e georreferenciamento.
#'
#' Verifica explicitamente o ganho da normalizacao da chave. Sem remover o
#' espaco de "REC 1001", a juncao perde 370 armadilhas sem avisar.
diagnosticar_juncao <- function(leituras, geo) {
  ids_leitura <- unique(leituras$id_ovt)
  ids_geo     <- unique(geo$id_ovt)

  # A juncao como seria sem a normalizacao: os identificadores exatamente
  # como estao gravados em cada arquivo.
  ids_leitura_cru <- unique(str_trim(leituras$id_ovt_cru))
  ids_geo_cru     <- unique(str_trim(geo$id_ovt_cru))

  tibble::tibble(
    item = c(
      "armadilhas nas leituras",
      "armadilhas no georreferenciamento",
      "casadas sem normalizar a chave",
      "casadas com a chave normalizada",
      "ganho da normalizacao",
      "leituras sem georreferencia"
    ),
    valor = c(
      length(ids_leitura),
      length(ids_geo),
      length(intersect(ids_leitura_cru, ids_geo_cru)),
      length(intersect(ids_leitura, ids_geo)),
      length(intersect(ids_leitura, ids_geo)) -
        length(intersect(ids_leitura_cru, ids_geo_cru)),
      length(setdiff(ids_leitura, ids_geo))
    )
  )
}


#' Diagnostico da qualidade espacial.
diagnosticar_espacial <- function(geo, pontos_edl) {
  tibble::tibble(
    item = c(
      "armadilhas georreferenciadas",
      "armadilhas sem coordenada valida",
      "pontos estrategicos",
      "pontos com coordenada",
      "EDLs no cadastro",
      "EDLs visiveis no mapa",
      "EDLs sem coordenada"
    ),
    valor = c(
      sum(!is.na(geo$lat)),
      sum(is.na(geo$lat)),
      nrow(pontos_edl),
      sum(!is.na(pontos_edl$lat)),
      sum(pontos_edl$qt_edl, na.rm = TRUE),
      sum(pontos_edl$qt_edl[!is.na(pontos_edl$lat)], na.rm = TRUE),
      sum(pontos_edl$qt_edl, na.rm = TRUE) -
        sum(pontos_edl$qt_edl[!is.na(pontos_edl$lat)], na.rm = TRUE)
    )
  )
}


#' Verificacoes que devem passar para a saida ser confiavel.
#'
#' Cada linha compara um valor medido contra o que a analise das bases
#' estabeleceu. Uma falha nao interrompe a execucao: ela aparece no
#' relatorio para quem for usar o resultado decidir.
verificar <- function(leituras, geo, pontos_edl) {
  checagens <- list(
    list(
      nome = "toda leitura tem identificador de armadilha",
      ok = all(!is.na(leituras$id_ovt) & leituras$id_ovt != "")
    ),
    list(
      nome = "nenhuma contagem de ovos negativa",
      ok = all(leituras$n_ovos >= 0, na.rm = TRUE)
    ),
    list(
      nome = "coordenadas das armadilhas dentro do Recife",
      ok = all(
        is.na(geo$lat) |
          (geo$lat >= LIM_LAT[1] & geo$lat <= LIM_LAT[2]),
        na.rm = FALSE
      )
    ),
    list(
      nome = "toda latitude e longitude e negativa",
      ok = all(geo$lat < 0, na.rm = TRUE) && all(geo$lon < 0, na.rm = TRUE)
    ),
    list(
      nome = "mais de 80% das leituras com coordenada",
      ok = sum(!is.na(geo$lat)) / nrow(geo) > 0.80
    ),
    list(
      nome = "todos os oito distritos presentes nas leituras",
      ok = n_distinct(leituras$ds) == 8
    ),
    list(
      nome = "todos os oito distritos presentes no cadastro de EDL",
      ok = n_distinct(pontos_edl$ds) == 8
    )
  )

  tibble::tibble(
    verificacao = vapply(checagens, `[[`, character(1), "nome"),
    resultado = vapply(
      checagens,
      function(c) if (isTRUE(c$ok)) "passou" else "FALHOU",
      character(1)
    )
  )
}


#' Imprime uma tabela com titulo, para o log da execucao.
imprimir_bloco <- function(titulo, tabela) {
  cat("\n", strrep("-", 62), "\n", titulo, "\n", strrep("-", 62), "\n",
      sep = "")
  print(as.data.frame(tabela), row.names = FALSE)
}
