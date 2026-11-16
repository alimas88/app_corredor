# ler_corredor(): conferência do .zip da área de estudo (interface atual)

test_that("lê o shapefile e devolve uma feição em SIRGAS 2000", {
  zip <- zip_shapefile(area_estudo_teste())

  lido <- ler_corredor(zip, "area.zip")

  expect_s3_class(lido, "sf")
  expect_equal(nrow(lido), 1)
  expect_equal(sf::st_crs(lido)$epsg, 4674L)
})

test_that("reprojeta para 4674 a partir de outro sistema", {
  utm <- sf::st_transform(area_estudo_teste(), 31983)   # SIRGAS 2000 / UTM 23S
  zip <- zip_shapefile(utm)

  lido <- ler_corredor(zip, "area.zip")

  expect_equal(sf::st_crs(lido)$epsg, 4674L)
  expect_equal(as.numeric(sf::st_bbox(lido)), as.numeric(sf::st_bbox(area_estudo_teste())),
               tolerance = 1e-5)
})

test_that("aceita o shapefile dentro de uma pasta e ignora os arquivos do macOS", {
  zip <- zip_shapefile(area_estudo_teste(), pasta = "dados/area",
                       extras = c("__MACOSX/dados/area/._area.shp", "dados/area/._area.shp"))

  expect_s3_class(ler_corredor(zip, "area.zip"), "sf")
})

test_that("aceita a extensão .ZIP em maiúsculas", {
  zip <- zip_shapefile(area_estudo_teste())
  expect_s3_class(ler_corredor(zip, "AREA.ZIP"), "sf")
})

test_that("recusa arquivo que não é .zip", {
  expect_error(ler_corredor(tempfile(), "area.kml"),
               "não é um .zip", class = "erro_entrada")
})

test_that("recusa .zip corrompido", {
  falso <- withr::local_tempfile(fileext = ".zip")
  writeLines("isto não é um zip", falso)

  expect_error(ler_corredor(falso, "area.zip"),
               "corrompido", class = "erro_entrada")
})

test_that("recusa .zip sem shapefile", {
  zip <- zip_shapefile(NULL, extras = "leia-me.txt")
  expect_error(ler_corredor(zip, "area.zip"),
               "não contém um shapefile \\(.shp\\) nem um geodatabase", class = "erro_entrada")
})

test_that("recusa .zip com mais de um shapefile", {
  zip <- zip_shapefile(area_estudo_teste(), extras = "outro.shp")
  expect_error(ler_corredor(zip, "area.zip"),
               "mais de um conjunto de dados", class = "erro_entrada")
})

test_that("aponta os arquivos obrigatórios que faltam", {
  expect_error(ler_corredor(zip_shapefile(area_estudo_teste(), sem = "dbf"), "a.zip"),
               "Falta no .zip o .dbf", class = "erro_entrada")
  expect_error(ler_corredor(zip_shapefile(area_estudo_teste(), sem = c("dbf", "shx")), "a.zip"),
               "o .dbf e o .shx", class = "erro_entrada")
  expect_error(ler_corredor(zip_shapefile(area_estudo_teste(), sem = "prj"), "a.zip"),
               "não tem o arquivo .prj", class = "erro_entrada")
})

test_that("recusa geometria que não é polígono", {
  linha <- sf::st_sf(id = 1L, geometry = sf::st_cast(sf::st_geometry(area_estudo_teste()),
                                                      "MULTILINESTRING"))
  expect_error(ler_corredor(zip_shapefile(linha), "a.zip"),
               "Geometria inadequada", class = "erro_entrada")
})

test_that("recusa mais de uma feição", {
  duas <- rbind(area_estudo_teste(), area_estudo_teste())
  expect_error(ler_corredor(zip_shapefile(duas), "a.zip"),
               "tem 2 feições", class = "erro_entrada")
})
