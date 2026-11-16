#' Converte o texto da distância de buffer em número
#'
#' @description A distância é digitada em km, no formato brasileiro. Com
#' vírgula, a vírgula é o separador decimal e os pontos são de milhar
#' ("1.250,5" = 1250,5). Sem vírgula, o ponto é decimal ("2.5" = 2,5). Aceita
#' "km" no fim e espaços.
#'
#' @param texto String digitada.
#'
#' @return Número em km, ou NA quando o texto não é um número não negativo.
#' @noRd
parse_distancia <- function(texto) {

  if (is.null(texto) || length(texto) != 1 || is.na(texto)) return(NA_real_)

  t <- texto |>
    stringr::str_remove_all("\\s") |>
    stringr::str_remove(stringr::regex("km$", ignore_case = TRUE))

  if (stringr::str_detect(t, ",")) {
    t <- t |> stringr::str_remove_all("\\.") |> stringr::str_replace(",", ".")
  }
  if (!stringr::str_detect(t, "^([0-9]+\\.?[0-9]*|\\.[0-9]+)$")) return(NA_real_)

  as.numeric(t)
}

#' Confere a distância de buffer digitada
#'
#' @description Feita para `validate()`: devolve NULL quando a distância é
#' válida e a mensagem para o usuário quando não é, sem calcular nada.
#'
#' ```r
#' distancia <- reactive({
#'   validate(conferir_distancia(input$distancia))
#'   parse_distancia(input$distancia)
#' })
#' ```
#'
#' @param texto String digitada.
#'
#' @return NULL ou string.
#' @noRd
conferir_distancia <- function(texto) {
  if (is.null(texto) || stringr::str_squish(texto) == "") {
    return("Informe a distância de buffer em km.")
  }
  d <- parse_distancia(texto)
  if (is.na(d)) return("Distância inválida. Use km, com vírgula decimal (ex.: 2,5 ou 0,04).")
  if (d <= 0) return("A distância de buffer deve ser maior que zero.")
  NULL
}

#' Gera a área de estudo a partir do traçado
#'
#' @description Ponto ou linha recebem o buffer geodésico da distância
#' informada (ver `buffer_geodesico()`). Polígono é a área de estudo enviada
#' pronta e é usado como veio, sem buffer.
#'
#' @param tracado sf com uma feição (saída de `ler_tracado()`).
#' @param distancia_km Distância de buffer em km. Obrigatória para ponto e
#'   linha; deve ser NULL para polígono.
#'
#' @return sf com uma feição em EPSG:4674 e a coluna `distancia_km` (NA para
#'   área de estudo enviada pronta).
#' @noRd
gerar_area_estudo <- function(tracado, distancia_km = NULL) {

  tipo <- tipo_geometria(tracado)
  geom <- sf::st_transform(sf::st_geometry(tracado), 4674)

  if (identical(tipo, "poligono")) {
    if (!is.null(distancia_km)) {
      erro_entrada("A área de estudo enviada pronta (polígono) não recebe buffer.")
    }
    return(sf::st_sf(distancia_km = NA_real_, geometry = geom))
  }

  if (is.na(tipo)) {
    erro_entrada("Geometria não aceita. Envie ponto, linha ou polígono.")
  }
  if (is.null(distancia_km) || is.na(distancia_km) || distancia_km <= 0) {
    erro_entrada("Informe a distância de buffer (maior que zero) para o traçado.")
  }

  sf::st_sf(distancia_km = distancia_km,
            geometry = buffer_geodesico(geom, distancia_km * 1000))
}

#' Área em km²
#'
#' @description Cálculo geodésico com o s2, na esfera. Pode diferir um pouco
#' do ArcGIS e do QGIS, que calculam no elipsoide.
#'
#' @param x sf ou sfc em coordenadas geográficas.
#'
#' @return Número.
#' @noRd
area_km2 <- function(x) {
  sum(as.numeric(sf::st_area(x))) / 1e6
}

#' Buffer geodésico de pontos e linhas
#'
#' @description O `st_buffer()` do `sf` em coordenadas geográficas usa o s2,
#' que aproxima o buffer por células: com os parâmetros padrão, um buffer de
#' 40 m num traçado de 2.600 km chegava a 5 km do eixo (ver "Buffer geodésico"
#' em `dev/DECISOES.md`). Aqui, cada ponto e cada trecho de linha de até
#' `trecho_m` é projetado numa azimutal equidistante (elipsoide GRS80, o do
#' SIRGAS 2000) centrada nele, recebe o buffer em metros e volta a 4674. As
#' partes são unidas num só polígono.
#'
#' @param geom sfc de pontos ou linhas, em EPSG:4674.
#' @param dist_m Distância em metros.
#' @param trecho_m Comprimento máximo de cada trecho de linha, em metros. Até
#'   50 km do centro, a distorção da projeção é desprezível.
#' @param n_quad Segmentos por quarto de círculo nas pontas e curvas.
#' @param folga Fração de `dist_m` usada para simplificar o polígono (ver
#'   `buffer_local()`). A borda fica entre `dist_m` e `dist_m * (1 + 2 * folga)`
#'   do traçado: nunca menor que a distância pedida.
#'
#' @return sfc com um polígono (ou multipolígono), em EPSG:4674.
#' @noRd
buffer_geodesico <- function(geom, dist_m, trecho_m = 50000, n_quad = 90, folga = 5e-4) {

  tipo <- tipo_geometria(geom)
  geom <- sf::st_geometry(geom)

  partes <- if (tipo == "ponto") {
    xy <- sf::st_coordinates(sf::st_cast(geom, "POINT"))[, 1:2, drop = FALSE]
    purrr::map(seq_len(nrow(xy)), \(i) xy[i, , drop = FALSE])
  } else {
    sf::st_cast(geom, "LINESTRING") |>
      purrr::map(\(l) dividir_linha(sf::st_coordinates(l)[, 1:2, drop = FALSE], trecho_m)) |>
      purrr::list_flatten()
  }

  buffers <- purrr::map(partes, \(xy) buffer_local(xy, dist_m, n_quad, tol = dist_m * folga))

  # As partes se sobrepõem nas emendas; a união no plano basta para isso.
  s2_antes <- suppressMessages(sf::sf_use_s2(FALSE))
  on.exit(suppressMessages(sf::sf_use_s2(s2_antes)), add = TRUE)
  suppressMessages(sf::st_union(do.call(c, buffers))) |> sf::st_make_valid()
}

#' Buffer de um ponto ou trecho numa azimutal equidistante centrada nele
#'
#' @description Um traçado real tem milhares de vértices, e cada curva ganha um
#' arco de `n_quad` segmentos: sem simplificar, um buffer de 40 m num traçado de
#' 2.800 km com 20 mil vértices tinha 640 mil vértices, e a área de estudo vai
#' no texto de cada consulta ao banco. O buffer é feito com `dist_m + tol` e
#' simplificado com tolerância `tol` (Douglas-Peucker, em metros): a borda se
#' afasta no máximo `tol` da original, então continua a pelo menos `dist_m`.
#'
#' @param tol Tolerância da simplificação, em metros.
#' @noRd
buffer_local <- function(xy, dist_m, n_quad, tol) {

  centro <- colMeans(xy)
  crs_local <- sprintf("+proj=aeqd +lat_0=%.10f +lon_0=%.10f +ellps=GRS80 +units=m +no_defs",
                       centro[2], centro[1])
  parte <- if (nrow(xy) == 1) sf::st_point(xy[1, ]) else sf::st_linestring(xy)

  sf::st_sfc(parte, crs = 4674) |>
    sf::st_transform(crs_local) |>
    sf::st_buffer(dist_m + tol, nQuadSegs = n_quad) |>
    sf::st_simplify(preserveTopology = TRUE, dTolerance = tol) |>
    sf::st_segmentize(1000) |>        # arestas longas não deformam ao voltar
    sf::st_transform(4674)
}

#' Divide uma linha em trechos de até `trecho_m`
#'
#' @description Densifica a linha pelo caminho geodésico (vértices a cada
#' `passo_m`, no máximo) e agrupa os vértices em trechos consecutivos. Trechos
#' vizinhos compartilham o vértice da emenda. A densificação importa: longe do
#' centro da projeção, a geodésica entre dois vértices vira uma curva, e com
#' vértices a cada 5 km o buffer de 40 m ficava até 6 mm mais estreito.
#'
#' @param xy Matriz de coordenadas (lon, lat).
#' @return Lista de matrizes de coordenadas.
#' @noRd
dividir_linha <- function(xy, trecho_m, passo_m = 1000) {

  xy <- densificar_geodesico(xy, passo_m)
  if (nrow(xy) < 2) return(list(xy))

  seg <- distancia_vertices(xy)
  grupo <- floor(c(0, cumsum(seg)) / trecho_m)

  inicio <- which(!duplicated(grupo))
  fim <- c(inicio[-1], nrow(xy))
  manter <- fim > inicio

  purrr::map2(inicio[manter], fim[manter], \(i, f) xy[i:f, , drop = FALSE])
}

#' Insere vértices no caminho geodésico onde a distância passa de `passo_m`
#' @noRd
densificar_geodesico <- function(xy, passo_m) {

  if (nrow(xy) < 2) return(xy)
  seg <- distancia_vertices(xy)

  pedacos <- purrr::map(seq_along(seg), function(k) {
    n <- max(1, ceiling(seg[k] / passo_m))
    if (n == 1) return(xy[k + 1, , drop = FALSE])
    linha <- s2::s2_make_line(xy[k:(k + 1), 1], xy[k:(k + 1), 2])
    pts <- s2::s2_interpolate_normalized(linha, seq_len(n) / n)
    cbind(s2::s2_x(pts), s2::s2_y(pts))
  })

  do.call(rbind, c(list(xy[1, , drop = FALSE]), pedacos))
}

#' Distância geodésica, em metros, entre vértices consecutivos
#' @noRd
distancia_vertices <- function(xy) {
  n <- nrow(xy)
  s2::s2_distance(s2::s2_lnglat(xy[-n, 1], xy[-n, 2]),
                  s2::s2_lnglat(xy[-1, 1], xy[-1, 2]))
}
