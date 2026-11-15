# Integração com o SQL Server: consultas reais num banco de teste local
# (SQL Server 2022 em Docker, ver dev/bd_teste.sh), com tabelas TESTE_
# sintéticas. Pulados quando não há banco de teste.

#' Tema vetorial de teste. As colunas seguem a ordem de uma tabela do ArcGIS,
#' com uma nvarchar(max) antes das demais (o driver ODBC exige as (max) no fim
#' do SELECT) e a GDB_GEOMATTR_DATA.
criar_tema_vetor <- function(con, env = parent.frame()) {

  area <- area_estudo_teste()
  dentro <- "POINT (-47.6 -15.65)"   # vértice do traçado de teste
  bbox <- sf::st_bbox(area)
  # dentro do retângulo envolvente, mas longe do corredor (canto noroeste)
  no_bbox <- sprintf("POINT (%f %f)", bbox[["xmin"]] + 0.02, bbox[["ymax"]] - 0.02)
  # polígono que cruza a borda da área de estudo
  cruza <- sf::st_as_text(sf::st_buffer(
    sf::st_cast(sf::st_geometry(area), "MULTILINESTRING") |> sf::st_cast("POINT") |> _[1],
    500))

  valores <- c(
    sprintf("(1, NULL, N'dentro', geometry::STGeomFromText('%s', 4674), 1, NULL)", dentro),
    "(2, N'texto longo', N'longe', geometry::STGeomFromText('POINT (-40 -10)', 4674), 1, NULL)",
    sprintf("(3, NULL, N'só no retângulo', geometry::STGeomFromText('%s', 4674), 1, NULL)", no_bbox),
    sprintf("(4, NULL, N'cruza a borda', geometry::STGeomFromText('%s', 4674), 1, 0x00)", cruza),
    sprintf("(5, NULL, N'dentro inativa', geometry::STGeomFromText('%s', 4674), 0, NULL)", dentro)
  )

  criar_tabela_teste(con, "TESTE_TEMA_VETOR", c(
    paste("CREATE TABLE TESTE_TEMA_VETOR (OBJECTID int NOT NULL PRIMARY KEY,",
          "observacao nvarchar(max), nome nvarchar(100), Shape geometry,",
          "ativo bit, GDB_GEOMATTR_DATA varbinary(max));"),
    paste("INSERT INTO TESTE_TEMA_VETOR VALUES", paste(valores, collapse = ", "), ";")
  ), env = env)
}

test_that("consultar_tema_bd() traz do banco só as feições da área de estudo", {
  con <- conectar_bd_teste()
  criar_tema_vetor(con)

  r <- consultar_tema_bd(con, "TESTE_TEMA_VETOR", area_estudo_teste())

  expect_s3_class(r, "sf")
  expect_equal(sort(r$nome), sort(c("dentro", "cruza a borda", "dentro inativa")))
  expect_named(r, c("OBJECTID", "nome", "ativo", "observacao", "Shape"))
  expect_equal(sf::st_crs(r)$epsg, 4674L)
})

test_that("o filtro no banco é pelo polígono, e não pelo retângulo envolvente", {
  con <- conectar_bd_teste()
  criar_tema_vetor(con)
  area <- area_estudo_teste()

  n_no_banco <- function(geom_sql) {
    DBI::dbGetQuery(con, paste0(
      "SELECT COUNT(*) AS n FROM TESTE_TEMA_VETOR WHERE Shape.STIntersects(", geom_sql, ") = 1;"
    ))$n
  }

  expect_equal(n_no_banco(sql_geometria(area)), 3)
  bbox <- sf::st_as_sfc(sf::st_bbox(area))
  expect_equal(n_no_banco(sql_geometria(bbox)), 4)   # o retângulo traria "só no retângulo"
})

test_that("consultar_tema_bd() aplica o filtro de linhas e aceita esquema e view", {
  con <- conectar_bd_teste()
  criar_tema_vetor(con)
  criar_tabela_teste(con, "TESTE_V_TEMA",
                     "CREATE VIEW TESTE_V_TEMA AS SELECT OBJECTID, nome, ativo, Shape FROM TESTE_TEMA_VETOR;",
                     tipo = "VIEW")

  ativos <- consultar_tema_bd(con, "dbo.TESTE_TEMA_VETOR", area_estudo_teste(),
                              filtro_row = rlang::expr(ativo))
  expect_setequal(ativos$nome, c("dentro", "cruza a borda"))

  view <- consultar_tema_bd(con, "TESTE_V_TEMA", area_estudo_teste())
  expect_named(view, c("OBJECTID", "nome", "ativo", "Shape"))
  expect_equal(nrow(view), 3)
})

test_that("tabela inexistente deixa o tema 'não verificado'", {
  con <- conectar_bd_teste()

  r <- verificar_tema(\() consultar_tema_bd(con, "TESTE_NAO_EXISTE", area_estudo_teste()))

  expect_equal(r$situacao, "não verificado")
  expect_match(r$erro, "não encontrada")
})

test_that("contar_raster_bd() lê os tiles do banco e conta igual ao raster original", {
  con <- conectar_bd_teste()
  area <- area_estudo_teste()
  dados <- tiles_teste(area, n_tiles = 3)

  criar_tabela_teste(con, "TESTE_TILES",
    "CREATE TABLE TESTE_TILES (tile_id int NOT NULL PRIMARY KEY, Shape geometry, tif varbinary(max));")
  DBI::dbExecute(con,
    "INSERT INTO TESTE_TILES (tile_id, Shape, tif) VALUES (?, geometry::STGeomFromText(?, 4674), ?);",
    params = list(dados$tabela$tile_id, dados$tabela$wkt, blob::as_blob(unclass(dados$tabela$tif))))

  contagem <- contar_raster_bd(con, "TESTE_TILES", area)

  referencia <- terra::crop(dados$raster, terra::vect(sf::st_transform(area, 4326)),
                            mask = TRUE, touches = FALSE) |>
    terra::freq()
  expect_equal(contagem$class_id, as.integer(referencia$value))
  expect_equal(contagem$n, referencia$count)

  legenda <- dplyr::tibble(class_id = c(3L, 15L, 21L), descricao = c("A", "B", "C"),
                           color = c("#000000", "#111111", "#222222"))
  r <- verificar_tema(\() resumir_raster_bd(con, "TESTE_TILES", area, legenda))
  expect_equal(r$situacao, "com interferência")
  expect_equal(sum(as.numeric(r$dados$percentagem)), 100, tolerance = 1e-6)
})
