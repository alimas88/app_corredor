# Legendas do MapBiomas, uma por coleção, empilhadas em `legenda_mapbiomas`
#
# Os CSVs ficam em data-raw/legendas_mapbiomas/ e nunca são apagados: guardam as
# legendas das coleções anteriores, para análises comparativas entre versões.
# Todos seguem o mesmo formato: class_id, level, descricao, color (UTF-8).
#
#   colecao_10.csv   exportado do legenda_mapbiomas.rda anterior
#                    (fonte: Codigos-da-legenda-colecao-10.csv do MapBiomas)
#   colecao_11.csv   montado a partir do PDF oficial da Coleção 11
#                    (CodigosDeLegenda_LegendCodes_MapBiomas_Brazil_Collection11_PDF.pdf,
#                    de 13/08/2026), com as 41 classes e o nível hierárquico
#
# Nova coleção: monte o CSV no mesmo formato, salve como colecao_<n>.csv nesta
# pasta e rode o script. As coleções são lidas pelo nome do arquivo.

library(dplyr)
library(readr)

pasta <- "data-raw/legendas_mapbiomas"


# Leitura de todas as coleções da pasta ------------------------------------------

arquivos <- list.files(pasta, pattern = "^colecao_\\d+\\.csv$", full.names = TRUE)

legenda_mapbiomas <- arquivos |>
  rlang::set_names(\(f) stringr::str_extract(basename(f), "\\d+")) |>
  purrr::map(\(f) read_csv(f, col_types = "iicc", locale = locale(encoding = "UTF-8"))) |>
  purrr::list_rbind(names_to = "colecao") |>
  mutate(colecao = as.integer(colecao),
         color   = tolower(color)) |>
  relocate(colecao, class_id, level, descricao, color) |>
  arrange(colecao)


# Conferências -------------------------------------------------------------------

stopifnot(
  "colunas fora do padrão"       = identical(names(legenda_mapbiomas),
                                             c("colecao", "class_id", "level", "descricao", "color")),
  "classe repetida numa coleção" = !anyDuplicated(select(legenda_mapbiomas, colecao, class_id)),
  "class_id ou level vazio"      = !anyNA(select(legenda_mapbiomas, class_id, level)),
  "cor fora do padrão #rrggbb"   = all(grepl("^#[0-9a-f]{6}$", legenda_mapbiomas$color))
)

count(legenda_mapbiomas, colecao)   # esperado: 10 = 37 classes, 11 = 41 classes


# Diferenças entre coleções (só para conferência) ----------------------------------

col10 <- filter(legenda_mapbiomas, colecao == 10)
col11 <- filter(legenda_mapbiomas, colecao == 11)

# classes novas na 11; esperado: 7, 77, 84, 75, 91
anti_join(col11, col10, by = "class_id") |> select(class_id, level, descricao)

# classes da 10 que saíram na 11; esperado: 27 (Não observado)
anti_join(col10, col11, by = "class_id") |> select(class_id, level, descricao)

# classes com nome, nível ou cor diferente
inner_join(col10, col11, by = "class_id", suffix = c("_10", "_11")) |>
  filter(descricao_10 != descricao_11 | level_10 != level_11 | color_10 != color_11) |>
  select(class_id, descricao_10, descricao_11, level_10, level_11, color_10, color_11)


usethis::use_data(legenda_mapbiomas, overwrite = TRUE)
