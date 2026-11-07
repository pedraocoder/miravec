# 01_ingestao.R ---------------------------------------------------------
# Le as tres bases do MVP e devolve data frames em memoria, sem tratamento
# alem do necessario para a leitura ser correta.
#
#   F1  leituras de ovitrampa      -> ler_leituras()
#   F2  georreferenciamento        -> ler_georreferencia()
#   F3  pontos estrategicos e EDL  -> ler_pontos_edl()

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(readxl)
  library(stringr)
  library(tidyr)
})

DIR_BRUTOS <- file.path("dados", "brutos")

# O readxl infere o tipo de cada coluna pelas primeiras 1.000 linhas. Em
# DT_ENVIO_DS a primeira celula preenchida e a linha 17.767: com o padrao,
# a coluna inteira vira logical e os 13.687 valores somem sem erro. Este
# limite alto desliga o atalho.
LINHAS_PARA_INFERIR_TIPO <- 1e5


#' Localiza um arquivo pelo padrao do nome.
#'
#' Os nomes originais da GEVACZ sao longos e tem acentos e espacos
#' irregulares, entao o pipeline procura por padrao em vez de depender da
#' grafia exata.
localizar <- function(padrao) {
  achados <- list.files(
    DIR_BRUTOS, pattern = padrao, ignore.case = TRUE, full.names = TRUE
  )
  if (length(achados) == 0) {
    stop(
      "Nenhum arquivo em ", DIR_BRUTOS, " casa com o padrao: ", padrao,
      "\nVeja dados/brutos/README.md para a lista esperada.",
      call. = FALSE
    )
  }
  if (length(achados) > 1) {
    warning(
      "Mais de um arquivo casa com '", padrao, "'. Usando: ",
      basename(achados[1]),
      "\nO acervo tem copias duplicadas com conteudo divergente ",
      "(anomalia A6 do dicionario).",
      call. = FALSE
    )
  }
  achados[1]
}


#' F1: leituras de ovitrampa.
#'
#' A aba chama-se "CICLO 1" mas contem os 12 ciclos de 2026. A segunda aba
#' esta vazia.
ler_leituras <- function() {
  caminho <- localizar("PLANILHA.*GERAL.*OVT.*\\.xlsx$")
  log_etapa("lendo leituras: ", basename(caminho))

  bruto <- read_excel(caminho, sheet = 1, .name_repair = "minimal",
                      guess_max = LINHAS_PARA_INFERIR_TIPO)

  # O cabecalho da coluna de observacao traz a legenda inteira junto, entao
  # ela e localizada pelo prefixo e nao pelo nome completo.
  idx_obs <- which(str_starts(names(bruto), "OBS"))[1]
  obs_bruta <- if (is.na(idx_obs)) {
    rep(NA_character_, nrow(bruto))
  } else {
    as.character(bruto[[idx_obs]])
  }

  tibble::tibble(
    ano         = as.integer(bruto[["Ano"]]),
    ciclo       = as.integer(bruto[["CICLOS"]]),
    ds          = str_trim(as.character(bruto[["DS"]])),
    bairro      = str_trim(as.character(bruto[["BAIRRO"]])),
    bairro_area = str_trim(as.character(bruto[["BAIRRO_AREA"]])),
    id_ovt_cru  = as.character(bruto[["ID_OVT"]]),
    id_ovt      = normalizar_id_ovt(bruto[["ID_OVT"]]),
    n_ovos      = suppressWarnings(as.numeric(bruto[["N_OVOS"]])),
    obs         = str_to_upper(str_trim(obs_bruta)),
    dt_coleta   = como_data(bruto[["DT_COLETA"]]),
    dt_leitura  = como_data(bruto[["DT_LEITURA"]]),
    dt_dig      = como_data(bruto[["DT_DIG"]]),
    dt_envio_ds = como_data(bruto[["DT_ENVIO_DS"]])
  ) |>
    mutate(obs = na_if(obs, "NA"))
}


#' F2: coordenada de cada ovitrampa, uma aba por distrito.
#'
#' O cabecalho esta na linha 2 em todas as abas, mas a busca e feita por
#' conteudo para o pipeline nao quebrar se isso mudar. As coordenadas usam
#' os mesmos formatos sujos do cadastro de EDL.
ler_georreferencia <- function() {
  caminho <- localizar("GEORREFERENCIAMENTO.*OVT.*\\.xlsx$")
  log_etapa("lendo georreferenciamento: ", basename(caminho))

  abas <- excel_sheets(caminho)

  map_dfr(abas, function(aba) {
    linha_hdr <- achar_cabecalho(
      caminho, aba, c("ID OVT", "LATITUDE", "LONGITUDE"), minimo = 2
    )
    if (is.na(linha_hdr)) return(NULL)

    tabela <- suppressMessages(
      read_excel(caminho, sheet = aba, skip = linha_hdr - 1,
                 .name_repair = "minimal",
                 guess_max = LINHAS_PARA_INFERIR_TIPO)
    )
    names(tabela) <- str_to_upper(str_trim(names(tabela)))
    if (!all(c("ID OVT", "LATITUDE", "LONGITUDE") %in% names(tabela))) {
      return(NULL)
    }

    tabela |>
      filter(!is.na(.data[["ID OVT"]])) |>
      transmute(
        # O identificador cru e guardado para que o diagnostico possa
        # medir quanto a normalizacao da chave recupera.
        id_ovt_cru = as.character(.data[["ID OVT"]]),
        id_ovt = normalizar_id_ovt(.data[["ID OVT"]]),
        lat = map_dbl(LATITUDE,  ~ para_sul_oeste(ler_coordenada(.x, GRAU_LAT))),
        lon = map_dbl(LONGITUDE, ~ para_sul_oeste(ler_coordenada(.x, GRAU_LON)))
      )
  }) |>
    distinct(id_ovt, .keep_all = TRUE) |>
    validar_no_recife()
}


#' F3: pontos estrategicos e estacoes disseminadoras.
#'
#' Uma aba por distrito, com cabecalho na linha 4. A longitude ocupa a
#' coluna seguinte a de coordenadas, sem rotulo proprio. Um ponto
#' estrategico pode conter varias EDLs: o peso de cada ponto e o valor de
#' QUANT. DE EDL REAL.
ler_pontos_edl <- function() {
  caminho <- localizar("TOTAL.*EDL.*POR.*DS.*\\.xlsx$")
  log_etapa("lendo pontos estrategicos: ", basename(caminho))

  abas <- excel_sheets(caminho)

  map_dfr(seq_along(DS_ROMANO), function(i) {
    alvo <- paste0("DS ", i, " - TOTAL")
    aba <- abas[str_trim(abas) == alvo]
    if (length(aba) == 0) return(NULL)
    aba <- aba[1]

    linha_hdr <- achar_cabecalho(
      caminho, aba,
      c("TIPO PE", "LOGRADOURO", "BAIRRO", "COORDENADA"), minimo = 3
    )
    if (is.na(linha_hdr)) return(NULL)

    tabela <- suppressMessages(
      read_excel(caminho, sheet = aba, skip = linha_hdr - 1,
                 .name_repair = "minimal",
                 guess_max = LINHAS_PARA_INFERIR_TIPO)
    )
    tabela <- tabela[!is.na(tabela[[1]]), ]
    if (nrow(tabela) == 0) return(NULL)

    nomes <- str_to_upper(names(tabela))
    pos_coord <- which(str_detect(nomes, "COORDENADA"))[1]
    if (is.na(pos_coord)) return(NULL)

    col_ou_na <- function(padrao) {
      idx <- which(str_detect(nomes, padrao))[1]
      if (is.na(idx)) rep(NA_character_, nrow(tabela))
      else as.character(tabela[[idx]])
    }

    bruto_lat <- tabela[[pos_coord]]
    bruto_lon <- if (pos_coord + 1 <= ncol(tabela)) {
      tabela[[pos_coord + 1]]
    } else {
      rep(NA, nrow(tabela))
    }

    pares <- map2(bruto_lat, bruto_lon, ler_par_coord)

    idx_edl <- which(str_detect(nomes, "EDL REAL"))[1]

    tibble(
      ds      = DS_ROMANO[i],
      bairro  = str_trim(col_ou_na("BAIRRO")),
      tipo_pe = str_trim(col_ou_na("TIPO PE")),
      nome_pe = str_trim(col_ou_na("FANTASIA")),
      lat     = map_dbl(pares, "lat"),
      lon     = map_dbl(pares, "lon"),
      qt_edl  = if (is.na(idx_edl)) NA_real_
                else suppressWarnings(as.numeric(tabela[[idx_edl]]))
    )
  }) |>
    validar_no_recife()
}
