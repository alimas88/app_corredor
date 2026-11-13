# Legenda das classes de declividade (Embrapa, 1999) em `legenda_declividade`
#
# Fonte: data-raw/legenda_declividade.csv (class_id, descricao, lim_inf, lim_sup,
# color; UTF-8).
#   - class_id: valor do pixel no raster Topodata SC (INPE), de 1 a 6
#   - descricao, lim_inf, lim_sup: sistema Embrapa (1999), limites em %, no
#     intervalo [lim_inf, lim_sup); a última classe não tem limite superior
#   - color: rampa do verde (Plano) ao vermelho escuro (Escarpado). A simbologia
#     oficial do Topodata (topodata-qgis-qml.zip, SC.qml) só traz rótulos
#     "1" a "6" e tons de cinza.

library(dplyr)
library(readr)

legenda_declividade <- read_csv("data-raw/legenda_declividade.csv",
                                col_types = "icddc",
                                locale = locale(encoding = "UTF-8")) |>
  mutate(color = tolower(color)) |>
  arrange(class_id)


# Conferências -------------------------------------------------------------------

stopifnot(
  "colunas fora do padrão"      = identical(names(legenda_declividade),
                                            c("class_id", "descricao", "lim_inf", "lim_sup", "color")),
  "classes devem ser 1 a 6"     = identical(legenda_declividade$class_id, 1:6),
  "limites não encadeados"      = identical(head(lead(legenda_declividade$lim_inf), -1),
                                            head(legenda_declividade$lim_sup, -1)),
  "só a última classe é aberta" = identical(which(is.na(legenda_declividade$lim_sup)), 6L),
  "cor fora do padrão #rrggbb"  = all(grepl("^#[0-9a-f]{6}$", legenda_declividade$color))
)

legenda_declividade

usethis::use_data(legenda_declividade, overwrite = TRUE)
