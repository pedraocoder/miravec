# 02_indices.R ----------------------------------------------------------
# Calcula os indices oficiais da vigilancia entomologica e a latencia do
# processo, a partir das leituras ja ingeridas.

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
  library(rlang)
})

# Codigos de OBS que marcam armadilha sem leitura. Eles nao entram no
# denominador do IPO.
#
# PENDENTE DE CONFIRMACAO COM A GEVACZ: com esta regra o IPO fica entre
# 97% e 99,5% em todos os ciclos e distritos. Um indice que nao varia nao
# discrimina territorio nem periodo. Ver pergunta 1 do dicionario de dados.
OBS_SEM_LEITURA <- c("F", "E", "R", "D")


#' Marca cada leitura como examinada e positiva.
#'
#' Examinada: tem contagem numerica de ovos.
#' Positiva:  a contagem e maior que zero.
classificar_leituras <- function(leituras) {
  leituras |>
    mutate(
      sem_leitura = !is.na(obs) & obs %in% OBS_SEM_LEITURA,
      examinada   = !is.na(n_ovos),
      positiva    = examinada & n_ovos > 0
    )
}


#' IPO e IDO para qualquer agrupamento.
#'
#'   IPO = armadilhas positivas / armadilhas examinadas * 100
#'   IDO = total de ovos / armadilhas positivas
#'
#' @param leituras Saida de classificar_leituras().
#' @param ... Colunas de agrupamento, sem aspas. Sem nenhuma, agrega tudo.
calcular_indices <- function(leituras, ...) {
  leituras |>
    group_by(...) |>
    summarise(
      examinadas = sum(examinada, na.rm = TRUE),
      positivas  = sum(positiva, na.rm = TRUE),
      ovos       = sum(n_ovos, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(
      ipo = if_else(examinadas > 0, 100 * positivas / examinadas, NA_real_),
      ido = if_else(positivas  > 0, ovos / positivas,             NA_real_)
    )
}


#' Serie temporal dos indices pela data real de coleta.
#'
#' O numero do ciclo NAO delimita uma janela temporal: os ciclos se
#' sobrepoem muito (o ciclo 1 tem coletas de 26/01 a 25/03 e o ciclo 4 de
#' 10/03 a 20/05). Agrupar por ciclo e tratar o resultado como serie
#' temporal produz um grafico enganoso. Por isso a serie usa dt_coleta.
serie_mensal <- function(leituras) {
  leituras |>
    filter(!is.na(dt_coleta)) |>
    mutate(mes = floor_date(dt_coleta, "month")) |>
    calcular_indices(mes) |>
    arrange(mes)
}


#' Latencia entre as etapas do fluxo, em dias.
#'
#' A cadeia de datas da planilha permite medir o tempo entre a coleta em
#' campo e a disponibilizacao do resultado, indicador que a GEVACZ
#' reconhece como problema mas nao quantifica.
calcular_latencia <- function(leituras) {
  leituras |>
    transmute(
      ciclo,
      ds,
      coleta_leitura = as.numeric(dt_leitura  - dt_coleta),
      leitura_dig    = as.numeric(dt_dig      - dt_leitura),
      coleta_dig     = as.numeric(dt_dig      - dt_coleta),
      coleta_envio   = as.numeric(dt_envio_ds - dt_coleta)
    ) |>
    # Valores negativos ou absurdos sao erro de digitacao de data.
    mutate(across(
      coleta_leitura:coleta_envio,
      ~ if_else(.x >= 0 & .x < 400, .x, NA_real_)
    ))
}


#' Resumo da latencia, uma linha por etapa.
resumir_latencia <- function(latencia) {
  etapas <- c(
    "coleta_leitura" = "coleta -> leitura no laboratorio",
    "leitura_dig"    = "leitura -> digitacao",
    "coleta_dig"     = "coleta -> digitacao",
    "coleta_envio"   = "coleta -> envio ao distrito"
  )

  purrr::imap_dfr(etapas, function(rotulo, coluna) {
    valores <- latencia[[coluna]]
    valores <- valores[!is.na(valores)]
    tibble::tibble(
      etapa    = rotulo,
      n        = length(valores),
      mediana  = stats::median(valores),
      media    = round(mean(valores), 1),
      p90      = stats::quantile(valores, 0.9, names = FALSE),
      maximo   = max(valores)
    )
  })
}
