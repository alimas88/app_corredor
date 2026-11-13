# Corredor fictício para testes (`corredor`)
#
# Buffer de 2,5 km em torno de uma linha inventada no Brasil Central. Não
# representa nenhum empreendimento real; serve só para testar o app e as funções.

library(sf)
library(dplyr)

eixo <- st_linestring(rbind(
  c(-47.90, -15.80),
  c(-47.60, -15.65),
  c(-47.30, -15.55),
  c(-47.00, -15.30)
)) |>
  st_sfc(crs = 4674)

corredor <- st_sf(
  id = 1L,
  BUFF_DIST = 2500,
  geometry = st_buffer(eixo, dist = 2500)   # geodésico (s2), em metros
)

corredor

usethis::use_data(corredor, overwrite = TRUE)
