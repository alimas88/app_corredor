#' Contagem de pixels por valor de um raster em tiles no BD
#'
#' @description Lê do SQL Server os tiles GeoTIFF que intersectam `area`, monta
#' um mosaico virtual e conta os pixels de cada valor dentro da área. Serve para
#' qualquer raster gravado no padrão de `data-raw/carga_mapbiomas_col11_2025.R`
#' (colunas `tile_id`, `Shape` e `tif`).
#'
#' Entra na contagem o pixel cujo centro está dentro da área (`touches = FALSE`),
#' a mesma regra do `terra::extract()`. Pixels sem dado (NoData) não são
#' contados: os tiles só com NoData não foram gravados, então esses pixels nem
#' sempre chegam do banco, e contá-los daria resultados diferentes do raster
#' original.
#'
#' @param con Conexão DBI ao SQL Server.
#' @param tabela String. Nome da tabela de tiles.
#' @param area sf ou sfc com a área de estudo.
#' @param srid SRID da coluna `Shape`.
#'
#' @return tibble com `class_id` (valor do pixel) e `n` (número de pixels).
#'   Tem zero linhas se a área não tem pixel com dado.
#'
#' @noRd
contar_raster_bd <- function(con, tabela, area, srid = 4674) {

  vazio <- dplyr::tibble(class_id = integer(0), n = numeric(0))

  area <- area |>
    sf::st_geometry() |>
    sf::st_union() |>
    sf::st_make_valid() |>
    sf::st_transform(srid)

  # Filtra pelo polígono, não pelo bbox: uma área de estudo longa e diagonal
  # teria no bbox muito mais tiles do que os que ela realmente toca.
  # A coluna varbinary(max) precisa ser a última do SELECT (driver ODBC).
  tiles <- DBI::dbGetQuery(con, glue::glue(
    "SELECT tile_id, tif FROM {tabela} ",
    "WHERE Shape.STIntersects(",
    "geometry::STGeomFromText('{sf::st_as_text(area, digits = 7)}', {srid}).MakeValid()",
    ") = 1;"
  ))

  if (nrow(tiles) == 0) return(vazio)

  pasta <- tempfile("raster_bd_")
  dir.create(pasta)
  on.exit(unlink(pasta, recursive = TRUE), add = TRUE)

  arquivos <- file.path(pasta, paste0("tile_", tiles$tile_id, ".tif"))
  purrr::walk2(tiles$tif, arquivos, writeBin)

  # mosaico virtual: junta os tiles sem copiar pixels
  mosaico <- terra::vrt(arquivos, filename = file.path(pasta, "mosaico.vrt"))

  # recorte e máscara no CRS do raster; a contagem é feita dentro do terra,
  # sem trazer cada pixel para o R (bem mais rápido que extract + count)
  area_raster <- terra::vect(sf::st_transform(area, terra::crs(mosaico)))

  contagem <- terra::crop(mosaico, area_raster, mask = TRUE, touches = FALSE) |>
    terra::freq()

  if (is.null(contagem) || nrow(contagem) == 0) return(vazio)

  dplyr::tibble(class_id = as.integer(contagem$value), n = contagem$count)
}
