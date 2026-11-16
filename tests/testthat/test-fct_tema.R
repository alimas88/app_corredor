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

# Banco simulado: responde à consulta das colunas (INFORMATION_SCHEMA) e à das
# feições, como o SQL Server via ODBC (geometria em WKB, lista de raw)
colunas_bd <- data.frame(
  COLUMN_NAME = c("OBJECTID", "observacao", "nome", "Shape", "ativo", "GDB_GEOMATTR_DATA"),
  DATA_TYPE = c("int", "nvarchar", "nvarchar", "geometry", "bit", "varbinary"),
  CHARACTER_MAXIMUM_LENGTH = c(NA, -1, 100, -1, NA, -1)
)

feicoes_bd <- function() {
  area <- area_estudo_teste()
  dentro <- sf::st_centroid(sf::st_geometry(area))
  fora <- sf::st_set_crs(dentro + c(1, 1), 4674)   # a soma descarta o CRS
  data.frame(
    OBJECTID = 1:3,
    nome = c("dentro", "fora", "dentro inativa"),
    ativo = c(TRUE, TRUE, FALSE),
    observacao = NA_character_,
    wkb = I(unclass(sf::st_as_binary(c(dentro, fora, dentro))))
  )
}

banco_simulado <- function(env = parent.frame()) {
  consultas <- character(0)
  local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      consultas <<- c(consultas, statement)
      if (grepl("INFORMATION_SCHEMA", statement)) colunas_bd else feicoes_bd()
    },
    .package = "DBI", .env = env
  )
  function() consultas
}

test_that("consultar_tema_bd() devolve só as feições que intersectam a área de estudo", {
  consultas <- banco_simulado()

  r <- consultar_tema_bd("con", "TEMA_TESTE", area_estudo_teste())

  expect_s3_class(r, "sf")
  expect_equal(r$nome, c("dentro", "dentro inativa"))
  expect_equal(sf::st_crs(r)$epsg, 4674L)
  expect_named(r, c("OBJECTID", "nome", "ativo", "observacao", "Shape"))
  expect_true(sf::sf_use_s2())   # o s2 volta ao estado anterior
})

test_that("consultar_tema_bd() filtra no banco pelo polígono, com a geometria em WKB", {
  consultas <- banco_simulado()

  consultar_tema_bd("con", "TEMA_TESTE", area_estudo_teste())

  sql <- consultas()[2]
  expect_match(sql, "FROM TEMA_TESTE")
  # sem a Shape original nem a GDB_GEOMATTR_DATA; a coluna (max) vai para o fim
  expect_match(sql, "SELECT [OBJECTID], [nome], [ativo], [observacao], Shape.STAsBinary() AS wkb",
               fixed = TRUE)
  # o polígono da área de estudo, e não o retângulo envolvente (5 vértices)
  n_vertices <- lengths(regmatches(sql, gregexpr("-?[0-9.]+ -?[0-9.]+", sql)))
  expect_gt(n_vertices, 5)
})

test_that("consultar_tema_bd() aplica o filtro de linhas", {
  banco_simulado()

  r <- consultar_tema_bd("con", "TEMA_TESTE", area_estudo_teste(),
                         filtro_row = rlang::expr(ativo))

  expect_equal(r$nome, "dentro")
})

test_that("consultar_tema_bd() devolve sf vazio quando não há feições", {
  local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      if (grepl("INFORMATION_SCHEMA", statement)) colunas_bd
      else feicoes_bd()[0, ]
    },
    .package = "DBI"
  )

  r <- consultar_tema_bd("con", "TEMA_TESTE", area_estudo_teste())

  expect_s3_class(r, "sf")
  expect_equal(nrow(r), 0)
  expect_equal(resultado_tema(r)$situacao, "sem interferência")
})

test_that("colunas_tema_bd() falha quando a tabela não existe", {
  local_mocked_bindings(dbGetQuery = function(...) colunas_bd[0, ], .package = "DBI")
  expect_error(colunas_tema_bd("con", "dbo.TEMA_INEXISTENTE"), "não encontrada")
})

test_that("colunas_tema_bd() aceita esquema e escapa os nomes das colunas", {
  consulta <- NULL
  local_mocked_bindings(
    dbGetQuery = function(conn, statement, ...) {
      consulta <<- statement
      data.frame(COLUMN_NAME = "nome]estranho", DATA_TYPE = "nvarchar",
                 CHARACTER_MAXIMUM_LENGTH = 50)
    },
    .package = "DBI"
  )

  expect_equal(colunas_tema_bd("con", "dbo.TEMA"), "[nome]]estranho]")
  expect_match(consulta, "PARSENAME('dbo.TEMA', 2)", fixed = TRUE)
})

test_that("sql_geometria() não arredonda as coordenadas", {
  ponto <- sf::st_sfc(sf::st_point(c(-47.123456789, -15.987654321)), crs = 4674)

  sql <- sql_geometria(ponto)

  expect_match(sql, "-47.123456789 -15.987654321", fixed = TRUE)
  expect_match(sql, "', 4674).MakeValid()", fixed = TRUE)
})

test_that("ler_wkb() aceita a lista de raw e o blob do ODBC", {
  geom <- sf::st_geometry(area_estudo_teste())
  wkb <- unclass(sf::st_as_binary(geom))

  expect_equal(ler_wkb(wkb), geom, ignore_attr = TRUE)
  skip_if_not_installed("blob")
  expect_equal(ler_wkb(blob::as_blob(wkb)), geom, ignore_attr = TRUE)
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
