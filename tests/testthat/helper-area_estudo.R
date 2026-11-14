# Geometrias e arquivos de teste. Nada aqui representa empreendimento real.

#' Traçado fictício: linha inventada no Brasil Central (SIRGAS 2000)
tracado_teste <- function() {
  sf::st_linestring(rbind(
    c(-47.90, -15.80),
    c(-47.60, -15.65),
    c(-47.30, -15.55),
    c(-47.00, -15.30)
  )) |>
    sf::st_sfc(crs = 4674)
}

#' Área de estudo fictícia: buffer geodésico de 2,5 km em torno do traçado
area_estudo_teste <- function() {
  sf::st_sf(id = 1L, geometry = buffer_geodesico(tracado_teste(), 2500))
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

#' Grava camadas num arquivo de teste (.gpkg, .kml, .kmz ou .zip com .gdb)
#'
#' @param camadas Lista nomeada de sf; cada elemento vira uma camada.
#' @param formato "gpkg", "kml", "kmz" ou "gdb".
#'
#' @return Caminho do arquivo.
arquivo_camadas <- function(camadas, formato, env = parent.frame()) {

  pasta <- withr::local_tempdir(.local_envir = env)
  gravar <- function(dsn, driver) {
    purrr::iwalk(camadas, \(x, nome) sf::st_write(x, dsn, layer = nome, driver = driver,
                                                   append = TRUE, quiet = TRUE))
  }

  switch(formato,
    gpkg = { arq <- file.path(pasta, "dados.gpkg"); gravar(arq, "GPKG"); arq },
    kml  = { arq <- file.path(pasta, "dados.kml"); gravar(arq, "LIBKML"); arq },
    kmz  = {
      gravar(file.path(pasta, "doc.kml"), "LIBKML")
      arq <- file.path(pasta, "dados.kmz")
      withr::with_dir(pasta, utils::zip(arq, "doc.kml", flags = "-q", zip = "zip"))
      arq
    },
    gdb  = {
      gravar(file.path(pasta, "dados.gdb"), "OpenFileGDB")
      arq <- file.path(pasta, "dados.zip")
      withr::with_dir(pasta, utils::zip(arq, list.files(".", recursive = TRUE, pattern = "",
                                                        include.dirs = FALSE) |>
                                          grep(pattern = "^dados\\.gdb/", value = TRUE),
                                        flags = "-q", zip = "zip"))
      arq
    }
  )
}
