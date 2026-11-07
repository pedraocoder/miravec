# setup_renv.R ----------------------------------------------------------
# Roda UMA VEZ, por quem cria o repositorio, para gerar o renv.lock.
# Quem clona depois nao usa este script: usa renv::restore().
#
#   Rscript setup_renv.R

pacotes <- c(
  "renv",
  "dplyr", "tidyr", "purrr", "stringr", "readr", "tibble",
  "readxl", "lubridate", "rlang"
)

faltando <- setdiff(pacotes, rownames(installed.packages()))
if (length(faltando) > 0) {
  cat("instalando:", paste(faltando, collapse = ", "), "\n")
  install.packages(faltando, repos = "https://cloud.r-project.org")
}

renv::init(bare = TRUE, restart = FALSE)
renv::snapshot(packages = setdiff(pacotes, "renv"), prompt = FALSE)

cat("\nrenv.lock gerado. Versione-o junto com o codigo.\n")
cat("A partir daqui, quem clonar o repositorio roda:\n")
cat("  Rscript -e 'renv::restore()'\n")
