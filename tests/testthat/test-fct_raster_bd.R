# contar_raster_bd(): o banco é simulado. A consulta devolve tiles GeoTIFF
# gerados aqui, no mesmo formato da carga (INT1U, uma linha por tile).

#' Raster de classes em WGS 84 (como o MapBiomas), cortado em tiles
tiles_teste <- function(area, n_tiles = 2) {
  ext <- terra::ext(sf::st_bbox(sf::st_transform(area, 4326))) + 0.05
  r <- terra::rast(ext, resolution = 0.01, crs = "EPSG:4326")
  terra::values(r) <- rep_len(c(3L, 15L, 21L, NA), terra::ncell(r))

  pasta <- withr::local_tempdir(.local_envir = parent.frame())
  arquivos <- terra::makeTiles(r, c(ceiling(terra::nrow(r) / n_tiles), terra::ncol(r)),
                               filename = file.path(pasta, "tile_.tif"),
                               datatype = "INT1U", NAflag = 0)
  list(
    raster = r,
    tabela = data.frame(
      tile_id = seq_along(arquivos),
      tif = I(lapply(arquivos, \(f) readBin(f, "raw", file.size(f))))
    )
  )
}

test_that("conta os pixels por classe igual ao raster original", {
  area <- area_estudo_teste()
  dados <- tiles_teste(area)
  consulta <- NULL
  local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) { consulta <<- statement; dados$tabela },
    .package = "DBI"
  )

  contagem <- contar_raster_bd(con = NULL, tabela = "TESTE_TILES", area = area)

  # referência: o raster inteiro, sem tiles, com a mesma regra do centro do pixel
  referencia <- terra::crop(dados$raster, terra::vect(sf::st_transform(area, 4326)),
                            mask = TRUE, touches = FALSE) |>
    terra::freq()

  expect_equal(contagem$class_id, as.integer(referencia$value))
  expect_equal(contagem$n, referencia$count)
  expect_false(anyNA(contagem$class_id))   # NoData não entra
  expect_match(consulta, "FROM TESTE_TILES")
  expect_match(consulta, "POLYGON")        # filtra pelo polígono, não pelo bbox
})

test_that("devolve tabela vazia quando não há tiles na área", {
  local_mocked_bindings(
    dbGetQuery = function(...) data.frame(tile_id = integer(0), tif = I(list())),
    .package = "DBI"
  )

  contagem <- contar_raster_bd(con = NULL, tabela = "TESTE_TILES", area = area_estudo_teste())

  expect_equal(nrow(contagem), 0)
  expect_named(contagem, c("class_id", "n"))
})
