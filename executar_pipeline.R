# executar_pipeline.R ---------------------------------------------------
# Ponto de entrada do pipeline MIRAVEC.
#
# Uso, a partir da raiz do repositorio:
#   Rscript executar_pipeline.R
#
# Le as planilhas de dados/brutos/, trata, calcula os indices e o
# cruzamento espacial, e escreve os resultados em dados/tratados/.
# Todos os caminhos sao relativos a raiz: o repositorio roda em qualquer
# maquina apos um clone limpo.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})

for (arquivo in c("utils.R", "01_ingestao.R", "02_indices.R",
                  "03_cobertura.R", "04_diagnostico.R")) {
  source(file.path("R", arquivo))
}

DIR_SAIDA <- file.path("dados", "tratados")
dir.create(DIR_SAIDA, showWarnings = FALSE, recursive = TRUE)

inicio <- Sys.time()
cat(strrep("=", 62), "\n")
cat("MIRAVEC - pipeline de preparacao\n")
cat(format(inicio, "%d/%m/%Y %H:%M:%S"), "\n")
cat(strrep("=", 62), "\n\n")


# 1. Ingestao -----------------------------------------------------------
leituras   <- ler_leituras()
geo        <- ler_georreferencia()
pontos_edl <- ler_pontos_edl()

imprimir_bloco("Base de leituras",      diagnosticar_leituras(leituras))
imprimir_bloco("Juncao com o georreferenciamento",
               diagnosticar_juncao(leituras, geo))
imprimir_bloco("Qualidade espacial",    diagnosticar_espacial(geo, pontos_edl))


# 2. Dado tidy ----------------------------------------------------------
# Uma observacao por linha: uma armadilha, num ciclo, com sua coordenada.
log_etapa("montando a base tidy")

leituras <- classificar_leituras(leituras)
tidy <- leituras |> left_join(geo, by = "id_ovt")


# 3. Indices ------------------------------------------------------------
log_etapa("calculando indices")

indices_ciclo_ds <- calcular_indices(tidy, ciclo, ds)
indices_bairro   <- calcular_indices(tidy, bairro)
indices_mes      <- serie_mensal(tidy)

imprimir_bloco(
  "Indices por mes de coleta",
  indices_mes |> mutate(ipo = round(ipo, 1), ido = round(ido, 1))
)


# 4. Latencia -----------------------------------------------------------
log_etapa("medindo a latencia do processo")

latencia <- calcular_latencia(tidy)
imprimir_bloco("Latencia em dias", resumir_latencia(latencia))


# 5. Cobertura ----------------------------------------------------------
log_etapa("cruzando ovitrampas com estacoes disseminadoras")

armadilhas <- tidy |>
  filter(!is.na(lat)) |>
  group_by(id_ovt) |>
  summarise(
    ds = first(ds), bairro = first(bairro),
    lat = first(lat), lon = first(lon),
    .groups = "drop"
  )

confianca <- confiabilidade_por_ds(pontos_edl)
cobertura <- armadilhas |>
  distancia_ate_edl(pontos_edl) |>
  classificar_cobertura(confianca)

imprimir_bloco("Confiabilidade do cruzamento por distrito", confianca)
imprimir_bloco("Cobertura por distrito", resumo_cobertura(cobertura))
imprimir_bloco(
  "Bairros sem nenhuma EDL no raio",
  candidatos_a_lacuna(cobertura, indices_bairro)
)


# 6. Verificacoes -------------------------------------------------------
imprimir_bloco("Verificacoes", verificar(leituras, geo, pontos_edl))


# 7. Saida --------------------------------------------------------------
log_etapa("gravando em ", DIR_SAIDA)

write_csv(tidy,             file.path(DIR_SAIDA, "leituras_tidy.csv"))
write_csv(cobertura,        file.path(DIR_SAIDA, "cobertura_armadilhas.csv"))
write_csv(pontos_edl,       file.path(DIR_SAIDA, "pontos_edl.csv"))
write_csv(indices_ciclo_ds, file.path(DIR_SAIDA, "indices_ciclo_ds.csv"))
write_csv(indices_bairro,   file.path(DIR_SAIDA, "indices_bairro.csv"))
write_csv(indices_mes,      file.path(DIR_SAIDA, "indices_mes.csv"))
write_csv(confianca,        file.path(DIR_SAIDA, "confiabilidade_ds.csv"))

cat("\n", strrep("=", 62), "\n", sep = "")
cat("concluido em ",
    round(as.numeric(difftime(Sys.time(), inicio, units = "secs")), 1),
    " s\n", sep = "")
cat(strrep("=", 62), "\n")
