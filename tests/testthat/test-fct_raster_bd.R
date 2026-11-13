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

legenda_teste <- dplyr::tibble(
  class_id = c(3L, 15L, 21L, 33L),
  descricao = c("Floresta", "Pastagem", "Mosaico", "Água"),
  faixa = c("a", "b", "c", "d"),
  color = c("#1f8d49", "#edde8e", "#ffefc3", "#2532e4")
)

test_that("percentual_classes() calcula o % sobre os pixels com dado", {
  contagem <- dplyr::tibble(class_id = c(15L, 3L), n = c(1, 3))

  r <- percentual_classes(contagem, legenda_teste)

  expect_named(r, c("class_id", "percentagem", "descricao", "faixa", "color"))
  expect_equal(r$class_id, c(3L, 15L))   # decrescente por percentagem
  expect_equal(as.numeric(r$percentagem), c(75, 25))
})

test_that("percentual_classes() segue a ordem da legenda e inclui as classes ausentes", {
  contagem <- dplyr::tibble(class_id = c(21L, 3L, 99L), n = c(1, 2, 1))

  r <- percentual_classes(contagem, legenda_teste, ordem = "classe", todas_classes = TRUE)

  expect_equal(r$class_id, c(3L, 15L, 21L, 33L, 99L))   # fora da legenda vai para o fim
  expect_equal(as.numeric(r$percentagem), c(50, 0, 25, 0, 25))
})

test_that("percentual_classes() não tem linhas quando a área não tem pixel com dado", {
  vazio <- dplyr::tibble(class_id = integer(0), n = numeric(0))

  r <- percentual_classes(vazio, legenda_teste, todas_classes = TRUE)

  expect_equal(nrow(r), 0)
  expect_named(r, c("class_id", "percentagem", "descricao", "faixa", "color"))
  expect_equal(resultado_tema(r)$situacao, "sem interferência")
})

test_that("validar_legenda() recusa legenda vazia, incompleta ou com classe repetida", {
  expect_invisible(validar_legenda(legenda_teste, "Teste"))
  expect_error(validar_legenda(legenda_teste[0, ], "Teste"), "vazia")
  expect_error(validar_legenda(dplyr::select(legenda_teste, -color), "Teste"), "color")
  expect_error(validar_legenda(dplyr::bind_rows(legenda_teste, legenda_teste), "Teste"),
               "repetido")
})
