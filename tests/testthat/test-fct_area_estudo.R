# Distância de buffer e geração da área de estudo

test_that("parse_distancia() entende o formato brasileiro", {
  expect_equal(parse_distancia("2,5"), 2.5)
  expect_equal(parse_distancia("0,04"), 0.04)
  expect_equal(parse_distancia(" 2,5 km "), 2.5)
  expect_equal(parse_distancia("1.250,5"), 1250.5)
  expect_equal(parse_distancia("2.5"), 2.5)
  expect_equal(parse_distancia("10"), 10)
  expect_equal(parse_distancia(",5"), 0.5)
  expect_equal(parse_distancia("2,"), 2)   # enquanto a pessoa digita
})

test_that("parse_distancia() devolve NA para o que não é número", {
  for (x in list("", "abc", "2,5,1", "-2", "2e3", ",", NA, NULL, c("1", "2"))) {
    expect_true(is.na(parse_distancia(x)), label = deparse(x))
  }
})

test_that("conferir_distancia() serve ao validate(): NULL ou mensagem", {
  expect_null(conferir_distancia("2,5"))
  expect_match(conferir_distancia(""), "Informe")
  expect_match(conferir_distancia("abc"), "inválida")
  expect_match(conferir_distancia("0"), "maior que zero")
})

# Distância geodésica exata, no elipsoide, de cada ponto ao alvo (traçado ou
# ponto): numa azimutal equidistante centrada no ponto, a distância a partir do
# centro é exata.
distancia_elipsoide <- function(pontos, alvo) {
  if (tipo_geometria(alvo) == "linha") {
    alvo <- sf::st_sfc(sf::st_linestring(
      densificar_geodesico(sf::st_coordinates(alvo)[, 1:2], 200)), crs = 4674)
  }
  xy <- sf::st_coordinates(pontos)
  vapply(seq_len(nrow(xy)), function(k) {
    crs <- sprintf("+proj=aeqd +lat_0=%.10f +lon_0=%.10f +ellps=GRS80 +units=m", xy[k, 2], xy[k, 1])
    as.numeric(sf::st_distance(sf::st_sfc(sf::st_point(c(0, 0)), crs = crs),
                               sf::st_transform(sf::st_geometry(alvo), crs)))
  }, numeric(1))
}

# A borda fica entre d e d * (1 + 2 * folga): nunca menor que a distância
# pedida (folga padrão de buffer_geodesico() = 0,05%). 1 mm de margem numérica.
expect_distancia <- function(dist, d, folga = 5e-4) {
  expect_gte(min(dist), d - 1e-3)
  expect_lte(max(dist), d * (1 + 2 * folga) + 1e-3)
}

vertices <- function(x) {
  sf::st_geometry(x) |>
    sf::st_cast("MULTILINESTRING") |>
    sf::st_cast("MULTIPOINT") |>
    sf::st_cast("POINT")
}

test_that("a borda do buffer da linha fica à distância pedida (40 m e 2,5 km)", {
  for (d in c(40, 2500)) {
    area <- gerar_area_estudo(sf::st_sf(geometry = tracado_teste()), distancia_km = d / 1000)
    set.seed(1)
    amostra <- sample(vertices(area), 100)
    expect_distancia(distancia_elipsoide(amostra, tracado_teste()), d)
    expect_equal(area$distancia_km, d / 1000)
  }
})

test_that("o buffer de um traçado longo é contínuo e preciso (trechos de 50 km)", {
  bipolo <- sf::st_sfc(sf::st_linestring(rbind(c(-60, -3), c(-55, -8), c(-50, -12))), crs = 4674)

  area <- gerar_area_estudo(sf::st_sf(geometry = bipolo), distancia_km = 0.04)

  expect_equal(length(sf::st_cast(sf::st_geometry(area), "POLYGON")), 1)   # sem emendas abertas
  set.seed(2)
  amostra <- sample(vertices(area), 100)
  expect_distancia(distancia_elipsoide(amostra, bipolo), 40)
  # área ≈ 2 × d × comprimento: o buffer por células do s2 dava ~45 vezes isso
  comprimento <- as.numeric(sf::st_length(bipolo))
  expect_equal(area_km2(area), 2 * 40 * comprimento / 1e6, tolerance = 0.01)
})

test_that("o buffer do ponto é um círculo do raio informado", {
  se <- sf::st_sf(geometry = sf::st_sfc(sf::st_point(c(-47.9, -15.8)), crs = 4674))

  area <- gerar_area_estudo(se, distancia_km = 10)

  expect_distancia(distancia_elipsoide(vertices(area)[1:50], se), 10000)
  expect_equal(area_km2(area), pi * 10^2, tolerance = 0.005)
})

test_that("polígono é usado como veio e não recebe buffer", {
  pronta <- area_estudo_teste()

  area <- gerar_area_estudo(pronta)

  expect_equal(sf::st_geometry(area), sf::st_geometry(pronta), ignore_attr = TRUE)
  expect_true(is.na(area$distancia_km))
  expect_error(gerar_area_estudo(pronta, 2.5), "não recebe buffer", class = "erro_entrada")
})

test_that("ponto e linha exigem distância maior que zero", {
  linha <- sf::st_sf(geometry = tracado_teste())
  expect_error(gerar_area_estudo(linha), "Informe a distância", class = "erro_entrada")
  expect_error(gerar_area_estudo(linha, 0), "Informe a distância", class = "erro_entrada")
})
