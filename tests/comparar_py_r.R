# comparar_py_r.R -------------------------------------------------------
# Confere a saida do pipeline em R contra a implementacao de referencia em
# Python. Divergencia entre as duas e tratada como erro ate ser explicada.
#
#   Rscript tests/comparar_py_r.R <pasta-com-a-saida-python>

args <- commandArgs(trailingOnly = TRUE)
dir_py <- if (length(args) > 0) args[1] else file.path("dados", "tratados_py")
dir_r  <- file.path("dados", "tratados")

if (!dir.exists(dir_py)) {
  stop(
    "Saida da referencia em Python nao encontrada em '", dir_py, "'.\n",
    "Gere-a antes com:\n",
    "  python referencia/python/constroi_base.py\n",
    "  python referencia/python/analise_cobertura.py",
    call. = FALSE
  )
}

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

comparar <- function(rotulo, valor_r, valor_py, tolerancia = 0) {
  dif <- abs(valor_r - valor_py)
  ok <- dif <= tolerancia
  cat(sprintf(
    "%-42s R=%-10s Py=%-10s %s\n",
    rotulo, format(valor_r), format(valor_py),
    if (ok) "igual" else sprintf("DIVERGE (%s)", format(dif))
  ))
  ok
}

cob_r  <- read_csv(file.path(dir_r,  "cobertura_armadilhas.csv"),
                   show_col_types = FALSE)
cob_py <- read_csv(file.path(dir_py, "cobertura_armadilhas.csv"),
                   show_col_types = FALSE)

cat(strrep("-", 80), "\n")
cat("Comparacao entre o pipeline em R e a referencia em Python\n")
cat(strrep("-", 80), "\n")

resultados <- c(
  comparar("armadilhas georreferenciadas",
           nrow(cob_r), nrow(cob_py)),
  comparar("distancia mediana ate a EDL (m)",
           round(median(cob_r$dist_edl_m)),
           round(median(cob_py$dist_edl_m)),
           tolerancia = 1),
  comparar("cobertas a 500 m",
           sum(cob_r$dist_edl_m <= 500),
           sum(cob_py$dist_edl_m <= 500)),
  comparar("distancia maxima (m)",
           round(max(cob_r$dist_edl_m)),
           round(max(cob_py$dist_edl_m)),
           tolerancia = 1)
)

# Latencia: a comparacao original nao cobria estas colunas, e foi por ai
# que passou o defeito de DT_DIG (serial do Excel lido como texto).
tidy_r  <- read_csv(file.path(dir_r,  "leituras_tidy.csv"),
                    show_col_types = FALSE)
tidy_py <- read_csv(file.path(dir_py, "leituras.csv"),
                    show_col_types = FALSE)

dias <- function(dados, de, para) {
  d <- as.numeric(as.Date(dados[[para]]) - as.Date(dados[[de]]))
  d[!is.na(d) & d >= 0 & d < 400]
}

for (par in list(
  c("dt_coleta",  "dt_leitura",  "DT_COLETA", "DT_LEITURA", "coleta -> leitura"),
  c("dt_leitura", "dt_dig",      "DT_LEITURA", "DT_DIG",    "leitura -> digitacao"),
  c("dt_coleta",  "dt_dig",      "DT_COLETA", "DT_DIG",     "coleta -> digitacao"),
  c("dt_coleta",  "dt_envio_ds", "DT_COLETA", "DT_ENVIO_DS", "coleta -> envio")
)) {
  v_r  <- dias(tidy_r,  par[1], par[2])
  v_py <- dias(tidy_py, par[3], par[4])
  resultados <- c(
    resultados,
    comparar(paste0(par[5], " (n)"), length(v_r), length(v_py),
             tolerancia = 2),
    comparar(paste0(par[5], " (mediana)"),
             median(v_r), median(v_py), tolerancia = 0)
  )
}

cat(strrep("-", 80), "\n")
if (all(resultados)) {
  cat("As duas implementacoes concordam.\n")
} else {
  cat("Ha divergencia. Investigue antes de usar a saida.\n")
  quit(status = 1)
}
