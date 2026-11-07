# utils.R ---------------------------------------------------------------
# Funcoes de apoio usadas por mais de uma etapa do pipeline.
# Todas as regras aqui vieram da analise das bases reais da GEVACZ e estao
# documentadas no Dicionario de Dados (epico E2).

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(readxl)
})

# Recife fica entre estas coordenadas. Serve para validar o que foi lido.
LIM_LAT <- c(-8.30, -7.90)
LIM_LON <- c(-35.05, -34.80)

# Magnitude esperada em graus inteiros. E ela que decide onde entra o
# separador decimal quando o numero foi gravado sem ele.
GRAU_LAT <- 8
GRAU_LON <- 34

DS_ROMANO <- c("I", "II", "III", "IV", "V", "VI", "VII", "VIII")


#' Normaliza o identificador da ovitrampa.
#'
#' A base de leituras grava `REC1001` e a de georreferenciamento grava
#' `REC 1001`. Sem remover o espaco, a juncao perde 370 das 2.871
#' armadilhas em silencio.
normalizar_id_ovt <- function(x) {
  x |>
    as.character() |>
    str_replace_all("\\s+", "") |>
    str_to_upper() |>
    str_trim()
}


#' Converte um texto de coordenada para grau decimal.
#'
#' As bases da GEVACZ usam seis representacoes diferentes, as vezes na
#' mesma planilha:
#'   1. decimal correto           -8.059653
#'   2. inteiro sem separador     -8067246, 80137209, -79617167
#'   3. grau, minuto e segundo    8o4'52.59"S
#'   4. espaco como separador     8 0803258
#'   5. espaco depois do ponto    8. 0194858
#'   6. par numa celula so        -7.9942062, -34.8967671  (ver ler_par_coord)
#'
#' No formato 2 a escala varia de linha para linha, de 6 a 8 digitos, entao
#' um divisor fixo corromperia parte dos dados. A posicao do separador e
#' escolhida por qual resultado bate com `grau_alvo`.
#'
#' @param valor Texto ou numero lido da planilha.
#' @param grau_alvo GRAU_LAT para latitude, GRAU_LON para longitude.
#' @return Numero em grau decimal, ou NA_real_.
ler_coordenada <- function(valor, grau_alvo) {
  if (is.null(valor) || length(valor) == 0) return(NA_real_)
  texto <- str_trim(as.character(valor))
  if (is.na(texto) || texto == "" || str_to_lower(texto) == "nan") {
    return(NA_real_)
  }

  # Formato 3: grau, minuto e segundo.
  dms <- str_match(
    texto,
    "(\\d{1,3})\\s*[º°]\\s*(\\d{1,2})\\s*'\\s*([\\d.]+)"
  )
  if (!is.na(dms[1, 1])) {
    return(
      as.numeric(dms[1, 2]) +
        as.numeric(dms[1, 3]) / 60 +
        as.numeric(dms[1, 4]) / 3600
    )
  }

  # Formatos 4 e 5: o espaco aparece como separador ("8 0803258") e tambem
  # depois do ponto ("8. 0194858"). Remover todo espaco resolve os dois.
  limpo <- texto |>
    str_replace_all("\\s+", "") |>
    str_replace_all(",", ".")

  numero <- suppressWarnings(as.numeric(limpo))
  if (is.na(numero)) return(NA_real_)

  # Formato 1: ja esta na magnitude certa.
  if (abs(abs(numero) - grau_alvo) < 1) return(numero)

  # Formato 2: reinsere o separador na posicao que bate com a magnitude.
  digitos <- as.character(abs(trunc(numero)))
  for (corte in 1:3) {
    if (corte >= nchar(digitos)) break
    candidato <- as.numeric(
      paste0(str_sub(digitos, 1, corte), ".", str_sub(digitos, corte + 1))
    )
    if (!is.na(candidato) && abs(candidato - grau_alvo) < 1) return(candidato)
  }

  NA_real_
}


#' Forca o par de coordenadas para o quadrante sul-oeste.
#'
#' O sinal e gravado de forma inconsistente entre distritos: ha latitude
#' positiva onde deveria ser negativa. Como o municipio inteiro cabe no
#' quadrante sul-oeste, o sinal lido e descartado e reaplicado.
para_sul_oeste <- function(x) {
  ifelse(is.na(x), NA_real_, -abs(x))
}


#' Le um par de coordenadas, tratando o formato 6.
#'
#' Em alguns distritos latitude e longitude vem juntas numa celula de
#' texto, separadas por virgula.
#'
#' @return Lista com `lat` e `lon` em grau decimal.
ler_par_coord <- function(bruto_lat, bruto_lon) {
  texto <- str_trim(as.character(bruto_lat))

  combinado <- !is.na(texto) &&
    str_detect(texto, "-?\\d+\\.\\d+\\s*,\\s*-?\\d+\\.\\d+")

  if (combinado) {
    partes <- str_split(texto, "\\s*,\\s*", n = 2)[[1]]
    return(list(
      lat = para_sul_oeste(ler_coordenada(partes[1], GRAU_LAT)),
      lon = para_sul_oeste(ler_coordenada(partes[2], GRAU_LON))
    ))
  }

  list(
    lat = para_sul_oeste(ler_coordenada(bruto_lat, GRAU_LAT)),
    lon = para_sul_oeste(ler_coordenada(bruto_lon, GRAU_LON))
  )
}


#' Zera o par quando ele cai fora dos limites do Recife.
#'
#' Coordenada fora do municipio e erro de origem, nao de leitura. Marcar
#' como ausente e mais seguro do que plotar um ponto no oceano.
validar_no_recife <- function(dados) {
  dentro <- !is.na(dados$lat) & !is.na(dados$lon) &
    dados$lat >= LIM_LAT[1] & dados$lat <= LIM_LAT[2] &
    dados$lon >= LIM_LON[1] & dados$lon <= LIM_LON[2]

  dados$lat[!dentro] <- NA_real_
  dados$lon[!dentro] <- NA_real_
  dados
}


#' Descobre em que linha esta o cabecalho de uma aba.
#'
#' A posicao varia de 0 a 12 entre os arquivos da GEVACZ, entao ela nao
#' pode ser fixa. A linha do cabecalho e a primeira que contem pelo menos
#' `minimo` das palavras-chave do dominio.
#'
#' @return Indice da linha, base 1, ou NA_integer_.
achar_cabecalho <- function(caminho, aba, palavras, minimo = 3,
                            ate_linha = 25) {
  bruto <- suppressMessages(
    read_excel(caminho, sheet = aba, col_names = FALSE,
               n_max = ate_linha, .name_repair = "minimal")
  )
  if (nrow(bruto) == 0) return(NA_integer_)

  for (i in seq_len(nrow(bruto))) {
    linha <- bruto[i, ] |>
      unlist() |>
      as.character() |>
      str_to_upper() |>
      paste(collapse = " ")
    achados <- sum(str_detect(linha, str_to_upper(palavras)))
    if (achados >= minimo) return(i)
  }
  NA_integer_
}


#' Distancia em metros entre dois pontos, pela formula de haversine.
#'
#' Vetorizada: aceita vetores e devolve um vetor do mesmo tamanho.
distancia_m <- function(lat1, lon1, lat2, lon2) {
  raio <- 6371000
  rad <- pi / 180
  dlat <- (lat2 - lat1) * rad
  dlon <- (lon2 - lon1) * rad
  h <- sin(dlat / 2)^2 +
    cos(lat1 * rad) * cos(lat2 * rad) * sin(dlon / 2)^2
  2 * raio * asin(pmin(1, sqrt(h)))
}


# Datas fora desta faixa sao erro de digitacao, nao dado. A base cobre
# 2018 em diante; o limite superior protege contra o ano de cinco digitos
# que aparece em DT_DIG ("14/06/20260").
DATA_MINIMA <- as.Date("2015-01-01")
DATA_MAXIMA <- as.Date("2035-12-31")


#' Converte para Date, venha a coluna como data, numero ou texto.
#'
#' O readxl devolve POSIXct quando toda a coluna esta formatada como data.
#' Basta uma celula destoante para ele tipar a coluna inteira como texto, e
#' ai o serial do Excel aparece como "46088". Em DT_DIG e exatamente isso
#' que acontece: 30.461 seriais e uma unica data escrita a mao.
#'
#' Por isso a funcao nao escolhe uma estrategia: aplica o serial onde ele
#' existe, tenta os formatos de data no que sobrou, e descarta o que cair
#' fora de uma faixa plausivel.
como_data <- function(x) {
  if (inherits(x, "Date")) return(plausivel_ou_na(x))
  if (inherits(x, "POSIXct")) return(plausivel_ou_na(as.Date(x)))
  if (is.numeric(x)) {
    return(plausivel_ou_na(as.Date(x, origin = "1899-12-30")))
  }

  texto <- str_trim(as.character(x))
  texto[texto == "" | str_to_lower(texto) %in% c("na", "nan")] <- NA_character_

  saida <- as.Date(rep(NA_character_, length(texto)))

  # Serial do Excel gravado como texto.
  eh_serial <- !is.na(texto) & str_detect(texto, "^\\d{5}$")
  if (any(eh_serial)) {
    saida[eh_serial] <- as.Date(
      suppressWarnings(as.numeric(texto[eh_serial])), origin = "1899-12-30"
    )
  }

  # O que sobrou: data escrita por extenso. as.Date com tryFormats
  # interrompe a execucao quando nenhum formato casa, em vez de devolver
  # NA, entao o laco tenta um formato por vez.
  for (formato in c("%Y-%m-%d", "%d/%m/%Y", "%Y/%m/%d", "%d-%m-%Y")) {
    pendentes <- is.na(saida) & !is.na(texto)
    if (!any(pendentes)) break
    saida[pendentes] <- suppressWarnings(
      as.Date(texto[pendentes], format = formato)
    )
  }

  plausivel_ou_na(saida)
}


#' Zera datas fora da faixa plausivel.
plausivel_ou_na <- function(datas) {
  fora <- !is.na(datas) & (datas < DATA_MINIMA | datas > DATA_MAXIMA)
  datas[fora] <- NA
  datas
}


#' Mensagem de etapa, para acompanhar a execucao.
log_etapa <- function(...) {
  cat(format(Sys.time(), "[%H:%M:%S] "), ..., "\n", sep = "")
}
