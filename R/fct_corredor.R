#' Lê a área de estudo enviada em .zip (shapefile)
#'
#' @description Confere o conteúdo do `.zip` antes de ler e devolve a área de
#' estudo em SIRGAS 2000 (EPSG:4674). Cada problema gera um erro de classe
#' `erro_corredor`, com uma mensagem pronta para o usuário. O shapefile pode
#' estar na raiz do `.zip` ou dentro de uma pasta.
#'
#' @param caminho Caminho do arquivo no disco (`input$<id>$datapath`).
#' @param nome Nome original do arquivo (`input$<id>$name`), usado para conferir
#'   a extensão.
#'
#' @return sf com uma única feição de polígono, em EPSG:4674.
#' @noRd
ler_corredor <- function(caminho, nome = basename(caminho)) {

  # 1. É um .zip que abre? ----------------------------------------------------
  if (!stringr::str_detect(nome, stringr::regex("\\.zip$", ignore_case = TRUE))) {
    erro_corredor("O arquivo enviado (", nome, ") não é um .zip.")
  }

  conteudo <- tryCatch(
    utils::unzip(caminho, list = TRUE)$Name,
    error = function(e) NULL,
    warning = function(w) NULL
  )
  if (is.null(conteudo)) {
    erro_corredor("Não foi possível abrir o .zip. O arquivo pode estar corrompido.")
  }

  # descarta pastas e os arquivos de controle do macOS (__MACOSX/, ._arquivo),
  # que repetem o nome do .shp e contariam como um segundo shapefile
  arquivos <- conteudo[!stringr::str_detect(conteudo, "/$|^__MACOSX/|(^|/)\\._")]

  # 2. Um único shapefile, com os arquivos obrigatórios -------------------------
  shp <- arquivos[stringr::str_detect(arquivos, stringr::regex("\\.shp$", ignore_case = TRUE))]

  if (length(shp) == 0) {
    erro_corredor("O .zip não contém um shapefile (.shp).")
  }
  if (length(shp) > 1) {
    erro_corredor("O .zip contém mais de um shapefile (",
                  paste(basename(shp), collapse = ", "),
                  "). Envie um .zip só com o shapefile da área de estudo.")
  }

  # .dbf e .shx com o mesmo nome e na mesma pasta do .shp
  base <- stringr::str_remove(shp, stringr::regex("\\.shp$", ignore_case = TRUE))
  tem_extensao <- function(ext) tolower(paste0(base, ".", ext)) %in% tolower(arquivos)

  faltam <- purrr::discard(c("dbf", "shx"), tem_extensao)
  if (length(faltam) > 0) {
    erro_corredor("Falta no .zip o ", paste0(".", faltam, collapse = " e o "),
                  " do shapefile ", basename(shp), ".")
  }
  if (!tem_extensao("prj")) {
    erro_corredor("O shapefile ", basename(shp), " não tem o arquivo .prj ",
                  "(sistema de coordenadas). Inclua o .prj no .zip.")
  }

  # 3. Leitura ------------------------------------------------------------------
  zip_gdal <- normalizePath(caminho, winslash = "/", mustWork = TRUE)

  corredor <- tryCatch(
    sf::st_read(paste0("/vsizip/", zip_gdal, "/", shp), quiet = TRUE),
    error = function(e) NULL
  )
  if (is.null(corredor)) {
    erro_corredor("Não foi possível ler o shapefile ", basename(shp),
                  ". Os arquivos podem estar corrompidos.")
  }

  # 4. Conteúdo: um único polígono, com sistema de coordenadas ------------------
  if (nrow(corredor) == 0) {
    erro_corredor("O shapefile ", basename(shp), " não tem feições.")
  }
  if (is.na(sf::st_crs(corredor))) {
    erro_corredor("O sistema de coordenadas do .prj de ", basename(shp),
                  " não foi reconhecido.")
  }

  tipos <- unique(as.character(sf::st_geometry_type(corredor, by_geometry = TRUE)))
  if (!all(tipos %in% c("POLYGON", "MULTIPOLYGON"))) {
    erro_corredor("Geometria inadequada (", paste(tipos, collapse = ", "),
                  "). Envie um polígono: corredor ou área de estudo.")
  }
  if (nrow(corredor) > 1) {
    erro_corredor("O shapefile tem ", nrow(corredor), " feições. ",
                  "Envie uma única feição: corredor ou área de estudo.")
  }
  if (sf::st_is_empty(corredor)) {
    erro_corredor("A feição do shapefile ", basename(shp), " não tem geometria.")
  }

  sf::st_transform(corredor, crs = 4674)
}

#' Erro de validação da área de estudo
#'
#' @description Erro com classe própria, para separar os problemas previstos
#' no arquivo enviado (mensagem pronta para o usuário) dos erros inesperados.
#'
#' @param ... Partes da mensagem, unidas com `paste0()`.
#' @noRd
erro_corredor <- function(...) {
  stop(structure(
    class = c("erro_corredor", "error", "condition"),
    list(message = paste0(...), call = NULL)
  ))
}
