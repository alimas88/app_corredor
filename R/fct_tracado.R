#' Erro previsto no arquivo enviado
#'
#' @description Erro com classe própria (`erro_entrada`), para separar os
#' problemas previstos no arquivo enviado (mensagem pronta para o usuário) dos
#' erros inesperados.
#'
#' @param ... Partes da mensagem, unidas com `paste0()`.
#' @noRd
erro_entrada <- function(...) {
  stop(structure(
    class = c("erro_entrada", "error", "condition"),
    list(message = paste0(...), call = NULL)
  ))
}

#' Fonte de dados GDAL do arquivo enviado
#'
#' @description Confere o arquivo e devolve o caminho que o GDAL lê. Aceita:
#'   - `.zip` com um shapefile (com `.dbf`, `.shx` e `.prj`) ou com um `.gdb`,
#'     na raiz ou numa pasta. Os arquivos de controle do macOS (`__MACOSX/`,
#'     `._*`) são ignorados;
#'   - `.kml`, `.kmz` e `.gpkg`.
#'
#' @param caminho Caminho do arquivo no disco (`input$<id>$datapath`).
#' @param nome Nome original do arquivo (`input$<id>$name`), usado para saber
#'   o formato.
#'
#' @return String com o caminho para o GDAL (ex.: `/vsizip/...`).
#' @noRd
fonte_entrada <- function(caminho, nome = basename(caminho)) {

  ext <- tolower(tools::file_ext(nome))

  if (ext %in% c("kml", "gpkg")) return(caminho)
  if (!ext %in% c("zip", "kmz")) {
    erro_entrada("Formato não aceito (", nome, "). Envie .zip (shapefile ou .gdb), ",
                 ".kml, .kmz ou .gpkg.")
  }

  conteudo <- tryCatch(
    utils::unzip(caminho, list = TRUE)$Name,
    error = function(e) NULL,
    warning = function(w) NULL
  )
  if (is.null(conteudo)) {
    erro_entrada("Não foi possível abrir o .", ext, ". O arquivo pode estar corrompido.")
  }
  arquivos <- conteudo[!stringr::str_detect(conteudo, "^__MACOSX/|(^|/)\\._")]
  zip_gdal <- paste0("/vsizip/", normalizePath(caminho, winslash = "/", mustWork = TRUE), "/")

  # .kmz: um .zip com o .kml dentro (em geral, doc.kml)
  if (ext == "kmz") {
    kml <- arquivos[stringr::str_detect(arquivos, stringr::regex("\\.kml$", ignore_case = TRUE))]
    if (length(kml) == 0) erro_entrada("O .kmz não contém um .kml.")
    return(paste0(zip_gdal, kml[1]))
  }

  # .zip: um único conjunto de dados, shapefile ou geodatabase
  arquivos <- arquivos[!stringr::str_detect(arquivos, "/$")]
  shp <- arquivos[stringr::str_detect(arquivos, stringr::regex("\\.shp$", ignore_case = TRUE))]
  gdb <- arquivos |>
    stringr::str_extract(stringr::regex("^(.*?\\.gdb)/", ignore_case = TRUE), group = 1) |>
    stats::na.omit() |>
    unique()

  if (length(shp) + length(gdb) == 0) {
    erro_entrada("O .zip não contém um shapefile (.shp) nem um geodatabase (.gdb).")
  }
  if (length(shp) + length(gdb) > 1) {
    erro_entrada("O .zip contém mais de um conjunto de dados (",
                 paste(basename(c(shp, gdb)), collapse = ", "),
                 "). Envie um .zip só com o traçado ou a área de estudo.")
  }
  if (length(gdb) == 1) return(paste0(zip_gdal, gdb))

  # shapefile: .dbf, .shx e .prj com o mesmo nome e na mesma pasta do .shp
  base <- stringr::str_remove(shp, stringr::regex("\\.shp$", ignore_case = TRUE))
  tem_extensao <- function(e) tolower(paste0(base, ".", e)) %in% tolower(arquivos)

  faltam <- purrr::discard(c("dbf", "shx"), tem_extensao)
  if (length(faltam) > 0) {
    erro_entrada("Falta no .zip o ", paste0(".", faltam, collapse = " e o "),
                 " do shapefile ", basename(shp), ".")
  }
  if (!tem_extensao("prj")) {
    erro_entrada("O shapefile ", basename(shp), " não tem o arquivo .prj ",
                 "(sistema de coordenadas). Inclua o .prj no .zip.")
  }

  paste0(zip_gdal, shp)
}

#' Camadas com geometria do arquivo enviado
#'
#' @description Para a escolha da camada quando o arquivo tem mais de uma
#' (ex.: `.gpkg`, `.gdb` ou pastas do `.kml`). O KML não informa o tipo de
#' geometria das camadas, então nenhuma é descartada aqui: uma tabela sem
#' geometria é recusada na leitura (`ler_tracado()`).
#'
#' @inheritParams fonte_entrada
#'
#' @return tibble com `camada`, `geometria` (tipo informado pelo arquivo; vazio
#'   quando o formato não informa) e `feicoes` (número de feições).
#' @noRd
listar_camadas <- function(caminho, nome = basename(caminho)) {
  camadas_fonte(fonte_entrada(caminho, nome))
}

#' @noRd
camadas_fonte <- function(fonte) {

  camadas <- tryCatch(sf::st_layers(fonte), error = function(e) NULL)
  if (is.null(camadas) || length(camadas$name) == 0) {
    erro_entrada("Não foi possível ler o arquivo. Ele pode estar corrompido ou vazio.")
  }

  dplyr::tibble(
    camada = camadas$name,
    geometria = purrr::map_chr(camadas$geomtype, \(g) paste(stats::na.omit(g), collapse = ", ")),
    feicoes = as.integer(camadas$features)
  )
}

#' Tipo do traçado ou da área de estudo
#'
#' @param x sf ou sfc com uma feição.
#'
#' @return "ponto", "linha" ou "poligono"; NA para outros tipos.
#' @noRd
tipo_geometria <- function(x) {
  tipo <- as.character(sf::st_geometry_type(x, by_geometry = FALSE))
  if (tipo == "GEOMETRY") tipo <- as.character(sf::st_geometry_type(x)[1])
  switch(tipo,
         POINT = , MULTIPOINT = "ponto",
         LINESTRING = , MULTILINESTRING = "linha",
         POLYGON = , MULTIPOLYGON = "poligono",
         NA_character_)
}

#' Lê o traçado ou a área de estudo enviada
#'
#' @description Confere o arquivo e devolve uma única feição em SIRGAS 2000
#' (EPSG:4674): ponto ou linha (traçado, que recebe o buffer) ou polígono (área
#' de estudo pronta). Mais de uma feição é recusado: quando vários
#' empreendimentos são analisados juntos, o analista monta e envia uma só
#' geometria. Cada problema gera um erro de classe `erro_entrada`.
#'
#' @inheritParams fonte_entrada
#' @param camada Nome da camada. Obrigatório quando o arquivo tem mais de uma
#'   (ver `listar_camadas()`).
#'
#' @return sf com uma feição, sem Z/M, em EPSG:4674, com os atributos do arquivo.
#' @noRd
ler_tracado <- function(caminho, nome = basename(caminho), camada = NULL) {

  fonte <- fonte_entrada(caminho, nome)
  camadas <- camadas_fonte(fonte)

  if (is.null(camada)) {
    if (nrow(camadas) > 1) {
      erro_entrada("O arquivo tem ", nrow(camadas), " camadas (",
                   paste(camadas$camada, collapse = ", "), "). Escolha uma.")
    }
    camada <- camadas$camada
  } else if (!camada %in% camadas$camada) {
    erro_entrada("A camada ", camada, " não existe no arquivo.")
  }

  x <- tryCatch(sf::st_read(fonte, layer = camada, quiet = TRUE), error = function(e) NULL)
  if (is.null(x)) {
    erro_entrada("Não foi possível ler a camada ", camada, ". O arquivo pode estar corrompido.")
  }

  if (!inherits(x, "sf")) erro_entrada("A camada ", camada, " não tem geometria.")
  if (nrow(x) == 0) erro_entrada("A camada ", camada, " não tem feições.")
  if (is.na(sf::st_crs(x))) {
    erro_entrada("O sistema de coordenadas da camada ", camada, " não foi reconhecido.")
  }
  if (nrow(x) > 1) {
    erro_entrada("A camada ", camada, " tem ", nrow(x), " feições. Envie uma única feição: ",
                 "o traçado (ponto ou linha) ou a área de estudo (polígono).")
  }
  if (sf::st_is_empty(x)) erro_entrada("A feição da camada ", camada, " não tem geometria.")

  x <- sf::st_zm(x)   # o KML traz altitude
  if (is.na(tipo_geometria(x))) {
    erro_entrada("Geometria não aceita (", as.character(sf::st_geometry_type(x)),
                 "). Envie ponto, linha ou polígono.")
  }

  sf::st_transform(x, 4674)
}

#' Lê a área de estudo enviada em .zip (shapefile)
#'
#' @description Provisório, usado pela interface atual, que só aceita a área de
#' estudo pronta em shapefile. Vale até a interface passar a usar
#' `ler_tracado()`.
#'
#' @inheritParams fonte_entrada
#'
#' @return sf com uma única feição de polígono, em EPSG:4674.
#' @noRd
ler_corredor <- function(caminho, nome = basename(caminho)) {

  if (!stringr::str_detect(nome, stringr::regex("\\.zip$", ignore_case = TRUE))) {
    erro_entrada("O arquivo enviado (", nome, ") não é um .zip.")
  }

  x <- ler_tracado(caminho, nome)

  if (tipo_geometria(x) != "poligono") {
    erro_entrada("Geometria inadequada (", as.character(sf::st_geometry_type(x)),
                 "). Envie um polígono: corredor ou área de estudo.")
  }
  x
}
