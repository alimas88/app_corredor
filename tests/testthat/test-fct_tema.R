# Situação do tema e consulta dos temas vetoriais

test_that("resultado_tema() define a situação pela tabela de resultado", {
  expect_equal(resultado_tema(dplyr::tibble(x = 1))$situacao, "com interferência")
  expect_equal(resultado_tema(dplyr::tibble(x = numeric(0)))$situacao, "sem interferência")

  falhou <- resultado_tema(erro = simpleError("tempo esgotado"))
  expect_equal(falhou$situacao, "não verificado")
  expect_null(falhou$dados)
  expect_equal(falhou$erro, "tempo esgotado")
  expect_true(falhou$notificar)
})

test_that("verificar_tema() transforma qualquer erro em 'não verificado'", {
  expect_equal(verificar_tema(\() dplyr::tibble(x = 1))$situacao, "com interferência")

  falhou <- verificar_tema(\() stop("tabela inexistente"))
  expect_equal(falhou$situacao, "não verificado")
  expect_equal(falhou$erro, "tabela inexistente")
})

test_that("sem conexão o tema fica 'não verificado', sem aviso próprio", {
  r <- verificar_tema(\() consultar_tema_bd(NULL, "TEMA", area_estudo_teste()))

  expect_equal(r$situacao, "não verificado")
  expect_false(r$notificar)   # o app já avisa a falta de conexão uma única vez
})

# Feições simuladas como o SQL Server devolve: atributos + geometria em WKT
feicoes_bd <- function() {
  area <- area_estudo_teste()
  dentro <- sf::st_centroid(sf::st_geometry(area))
  fora <- sf::st_set_crs(dentro + c(1, 1), 4674)   # a soma descarta o CRS
  data.frame(
    nome = c("dentro", "fora", "dentro inativa"),
    ativo = c(TRUE, TRUE, FALSE),
    GDB_GEOMATTR_DATA = NA,
    wkt = sf::st_as_text(c(dentro, fora, dentro))
  )
}

test_that("consultar_tema_bd() devolve só as feições que intersectam a área de estudo", {
  consulta <- NULL
  local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) { consulta <<- statement; feicoes_bd() },
    .package = "DBI"
  )

  r <- consultar_tema_bd("con", "TEMA_TESTE", area_estudo_teste())

  expect_s3_class(r, "sf")
  expect_equal(r$nome, c("dentro", "dentro inativa"))
  expect_equal(sf::st_crs(r)$epsg, 4674L)
  expect_false(any(c("wkt", "GDB_GEOMATTR_DATA") %in% names(r)))
  expect_match(consulta, "FROM TEMA_TESTE")
  expect_true(sf::sf_use_s2())   # o s2 volta ao estado anterior
})

test_that("consultar_tema_bd() aplica o filtro de linhas", {
  local_mocked_bindings(dbGetQuery = function(...) feicoes_bd(), .package = "DBI")

  r <- consultar_tema_bd("con", "TEMA_TESTE", area_estudo_teste(),
                         filtro_row = rlang::expr(ativo))

  expect_equal(r$nome, "dentro")
})

test_that("ler_tema_arquivo() lê o arquivo e filtra pela área de estudo", {
  area <- area_estudo_teste()
  centro <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(area)))
  pontos <- sf::st_sf(
    nome = c("dentro", "fora"),
    geometry = sf::st_sfc(sf::st_point(centro), sf::st_point(centro + 1), crs = 4674)
  )
  arquivo <- withr::local_tempfile(fileext = ".gpkg")
  sf::st_write(pontos, arquivo, layer = "hidro", quiet = TRUE)

  expect_equal(ler_tema_arquivo(arquivo, "hidro", area)$nome, "dentro")
  expect_error(ler_tema_arquivo("", "hidro", area), "não configurado")
})
