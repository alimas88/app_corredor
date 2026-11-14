# Leitura do traçado ou da área de estudo: .zip (shapefile ou .gdb), .kml,
# .kmz e .gpkg

linha_teste <- function() sf::st_sf(nome = "LT", geometry = tracado_teste())
ponto_teste <- function() sf::st_sf(nome = "SE", geometry = sf::st_centroid(tracado_teste()))

test_that("lê ponto, linha e polígono de shapefile em .zip", {
  for (x in list(ponto_teste(), linha_teste(), area_estudo_teste())) {
    lido <- ler_tracado(zip_shapefile(x), "dados.zip")
    expect_equal(nrow(lido), 1)
    expect_equal(sf::st_crs(lido)$epsg, 4674L)
  }
  expect_equal(tipo_geometria(ler_tracado(zip_shapefile(ponto_teste()), "a.zip")), "ponto")
  expect_equal(tipo_geometria(ler_tracado(zip_shapefile(linha_teste()), "a.zip")), "linha")
})

test_that("lê .gpkg, .kml, .kmz e .gdb em .zip", {
  for (formato in c("gpkg", "kml", "kmz", "gdb")) {
    arq <- arquivo_camadas(list(tracado = linha_teste()), formato)
    lido <- ler_tracado(arq, basename(arq))
    expect_equal(tipo_geometria(lido), "linha", label = formato)
    expect_equal(sf::st_crs(lido)$epsg, 4674L)
    expect_equal(class(sf::st_geometry(lido)[[1]])[1], "XY", label = formato)   # sem Z/M
  }
})

test_that("com várias camadas, lista as camadas e exige a escolha de uma", {
  arq <- arquivo_camadas(list(se = ponto_teste(), lt = linha_teste()), "gpkg")

  camadas <- listar_camadas(arq, "dados.gpkg")
  expect_equal(camadas$camada, c("se", "lt"))
  expect_equal(camadas$feicoes, c(1L, 1L))

  expect_error(ler_tracado(arq, "dados.gpkg"), "tem 2 camadas \\(se, lt\\)",
               class = "erro_entrada")
  expect_equal(tipo_geometria(ler_tracado(arq, "dados.gpkg", camada = "se")), "ponto")
  expect_error(ler_tracado(arq, "dados.gpkg", camada = "xx"), "não existe",
               class = "erro_entrada")
})

test_that("recusa mais de uma feição, mesmo de linha", {
  segmentos <- rbind(linha_teste(), linha_teste())
  expect_error(ler_tracado(zip_shapefile(segmentos), "a.zip"),
               "tem 2 feições. Envie uma única feição", class = "erro_entrada")
})

test_that("recusa formato não aceito e .zip com mais de um conjunto de dados", {
  expect_error(ler_tracado(tempfile(), "area.dwg"), "Formato não aceito",
               class = "erro_entrada")
  zip <- zip_shapefile(linha_teste(), extras = "outro.gdb/a00000001.gdbtable")
  expect_error(ler_tracado(zip, "a.zip"), "mais de um conjunto de dados",
               class = "erro_entrada")
})

test_that("recusa camada sem geometria", {
  arq <- withr::local_tempfile(fileext = ".gpkg")
  sf::st_write(linha_teste(), arq, layer = "lt", quiet = TRUE)
  sf::st_write(data.frame(a = 1), arq, layer = "tabela", quiet = TRUE)

  expect_setequal(listar_camadas(arq, "a.gpkg")$camada, c("lt", "tabela"))
  expect_error(ler_tracado(arq, "a.gpkg", camada = "tabela"), "não tem geometria",
               class = "erro_entrada")
})

test_that("recusa .kmz sem .kml", {
  zip <- zip_shapefile(NULL, extras = "leia-me.txt")
  expect_error(ler_tracado(zip, "dados.kmz"), "não contém um .kml", class = "erro_entrada")
})

test_that("tipo_geometria() classifica os tipos simples e multi", {
  multi <- sf::st_cast(sf::st_geometry(area_estudo_teste()), "MULTIPOLYGON")
  expect_equal(tipo_geometria(multi), "poligono")
  expect_equal(tipo_geometria(sf::st_cast(tracado_teste(), "MULTILINESTRING")), "linha")
  colecao <- sf::st_sfc(sf::st_geometrycollection(list(sf::st_point(c(0, 0)))), crs = 4674)
  expect_true(is.na(tipo_geometria(colecao)))
})
