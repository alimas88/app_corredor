# Geometrias e arquivos de teste. Nada aqui representa empreendimento real.

#' Área de estudo fictícia: buffer geodésico de 2,5 km em torno de uma linha
#' inventada no Brasil Central (SIRGAS 2000).
area_estudo_teste <- function() {
  eixo <- sf::st_linestring(rbind(
    c(-47.90, -15.80),
    c(-47.60, -15.65),
    c(-47.30, -15.55),
    c(-47.00, -15.30)
  )) |>
    sf::st_sfc(crs = 4674)

  sf::st_sf(id = 1L, geometry = sf::st_buffer(eixo, dist = 2500))
}

#' Grava `dados` como shapefile e compacta num .zip temporário
#'
#' @param dados sf a gravar.
#' @param nome Nome base do shapefile.
#' @param pasta Pasta dentro do .zip ("" = raiz).
#' @param sem Extensões a retirar do .zip (ex.: "prj").
#' @param extras Caminhos relativos de arquivos extras a incluir (vazios).
#' @param env Ambiente que controla a remoção dos temporários.
#'
#' @return Caminho do .zip.
zip_shapefile <- function(dados, nome = "area", pasta = "", sem = character(0),
                          extras = character(0), env = parent.frame()) {

  raiz <- withr::local_tempdir(.local_envir = env)
  destino <- file.path(raiz, pasta)
  dir.create(destino, recursive = TRUE, showWarnings = FALSE)

  if (!is.null(dados)) {
    sf::st_write(dados, file.path(destino, paste0(nome, ".shp")),
                 quiet = TRUE)
  }
  arquivos <- list.files(destino, full.names = TRUE)
  file.remove(arquivos[tools::file_ext(arquivos) %in% sem])

  for (extra in extras) {
    dir.create(file.path(raiz, dirname(extra)), recursive = TRUE, showWarnings = FALSE)
    file.create(file.path(raiz, extra))
  }

  zip <- withr::local_tempfile(fileext = ".zip", .local_envir = env)
  withr::with_dir(raiz, utils::zip(zip, list.files(".", recursive = TRUE, all.files = TRUE),
                                         flags = "-q", zip = "zip"))
  zip
}
