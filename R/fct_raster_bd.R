#' Contagem de pixels por valor de um raster em tiles no BD
#'
#' @description Lê do SQL Server os tiles GeoTIFF que intersectam `area`, monta
#' um mosaico virtual e conta os pixels de cada valor dentro da área. Serve para
#' qualquer raster gravado no padrão de `data-raw/carga_mapbiomas_col11_2025.R`
#' (colunas `tile_id`, `Shape` e `tif`).
#'
#' Entra na contagem o pixel cujo centro está dentro da área (`touches = FALSE`),
#' a mesma regra do `terra::extract()`. Pixels sem dado (NoData) não são
#' contados: os tiles só com NoData não foram gravados, então esses pixels nem
#' sempre chegam do banco, e contá-los daria resultados diferentes do raster
#' original.
#'
#' @param con Conexão DBI ao SQL Server.
#' @param tabela String. Nome da tabela de tiles.
#' @param area sf ou sfc com a área de estudo.
#' @param srid SRID da coluna `Shape`.
#'
#' @return tibble com `class_id` (valor do pixel) e `n` (número de pixels).
#'   Tem zero linhas se a área não tem pixel com dado.
#'
#' @noRd
contar_raster_bd <- function(con, tabela, area, srid = 4674) {

  vazio <- dplyr::tibble(class_id = integer(0), n = numeric(0))

  area <- area |>
    sf::st_geometry() |>
    sf::st_union() |>
    sf::st_make_valid() |>
    sf::st_transform(srid)

  # Filtra pelo polígono, não pelo bbox: uma área de estudo longa e diagonal
  # teria no bbox muito mais tiles do que os que ela realmente toca.
  # A coluna varbinary(max) precisa ser a última do SELECT (driver ODBC).
  tiles <- DBI::dbGetQuery(con, glue::glue(
    "SELECT tile_id, tif FROM {tabela} ",
    "WHERE Shape.STIntersects({sql_geometria(area, srid)}) = 1;"
  ))

  if (nrow(tiles) == 0) return(vazio)

  pasta <- tempfile("raster_bd_")
  dir.create(pasta)
  on.exit(unlink(pasta, recursive = TRUE), add = TRUE)

  arquivos <- file.path(pasta, paste0("tile_", tiles$tile_id, ".tif"))
  purrr::walk2(tiles$tif, arquivos, writeBin)

  # mosaico virtual: junta os tiles sem copiar pixels
  mosaico <- terra::vrt(arquivos, filename = file.path(pasta, "mosaico.vrt"))

  # recorte e máscara no CRS do raster; a contagem é feita dentro do terra,
  # sem trazer cada pixel para o R (bem mais rápido que extract + count)
  area_raster <- terra::vect(sf::st_transform(area, terra::crs(mosaico)))

  contagem <- terra::crop(mosaico, area_raster, mask = TRUE, touches = FALSE) |>
    terra::freq()

  if (is.null(contagem) || nrow(contagem) == 0) return(vazio)

  dplyr::tibble(class_id = as.integer(contagem$value), n = contagem$count)
}

#' Percentual da área de estudo por classe de um raster
#'
#' @description Junta a contagem de pixels com a legenda. O percentual é
#' calculado só sobre os pixels com dado (ver `contar_raster_bd()`).
#'
#' @param contagem tibble com `class_id` e `n` (saída de `contar_raster_bd()`).
#' @param legenda data.frame validado por `validar_legenda()`. As colunas além de
#'   `class_id`, `descricao` e `color` (ex.: `faixa`) entram na tabela depois de
#'   `descricao`.
#' @param ordem "percentagem" (decrescente) ou "classe" (a ordem da `legenda`;
#'   valores de pixel fora da legenda vão para o fim).
#' @param todas_classes Se TRUE, inclui com 0 as classes da legenda que não
#'   ocorrem na área de estudo.
#'
#' @return tibble com `class_id`, `percentagem`, `descricao`, colunas extras da
#'   legenda e `color`. Sem linhas se a área não tem pixel com dado.
#' @noRd
percentual_classes <- function(contagem, legenda,
                               ordem = c("percentagem", "classe"),
                               todas_classes = FALSE) {

  ordem <- match.arg(ordem)

  if (nrow(contagem) == 0) {
    return(
      dplyr::tibble(class_id = integer(0), percentagem = character(0)) |>
        dplyr::bind_cols(legenda[0, setdiff(names(legenda), "class_id")]) |>
        dplyr::relocate(color, .after = dplyr::last_col())
    )
  }

  if (todas_classes) {
    contagem <- legenda |>
      dplyr::select(class_id) |>
      dplyr::full_join(contagem, by = "class_id") |>
      dplyr::mutate(n = dplyr::coalesce(n, 0))
  }

  contagem <- switch(
    ordem,
    percentagem = dplyr::arrange(contagem, dplyr::desc(n)),
    classe      = dplyr::arrange(contagem, match(class_id, legenda$class_id), class_id)
  )

  contagem |>
    dplyr::mutate(percentagem = format(100 * n / sum(n), scientific = FALSE)) |>
    dplyr::left_join(legenda, by = "class_id") |>
    dplyr::select(class_id, percentagem, descricao, dplyr::everything(), -n) |>
    dplyr::relocate(color, .after = dplyr::last_col())
}

#' Percentual da área de estudo por classe de um raster em tiles no BD
#'
#' @param con Conexão DBI ao SQL Server. NULL se a conexão falhou.
#' @param tabela String. Tabela de tiles.
#' @param area sf com a área de estudo.
#' @inheritParams percentual_classes
#'
#' @return tibble (ver `percentual_classes()`).
#' @noRd
resumir_raster_bd <- function(con, tabela, area, legenda,
                              ordem = c("percentagem", "classe"),
                              todas_classes = FALSE) {

  if (is.null(con)) parar_sem_conexao()

  contar_raster_bd(con, tabela, area) |>
    percentual_classes(legenda, ordem = ordem, todas_classes = todas_classes)
}

#' Confere a legenda de um raster de classes
#'
#' @description Uma legenda vazia ou incompleta impede o app de iniciar, com
#' mensagem (ex.: coleção do MapBiomas sem legenda no pacote).
#'
#' @param legenda data.frame com `class_id`, `descricao` e `color`.
#' @param tema String. Nome do tema, usado na mensagem.
#'
#' @return `legenda` (invisível).
#' @noRd
validar_legenda <- function(legenda, tema) {

  faltam <- setdiff(c("class_id", "descricao", "color"), names(legenda))
  if (length(faltam) > 0) {
    stop("Legenda de ", tema, " sem a(s) coluna(s): ", paste(faltam, collapse = ", "), ".")
  }
  if (nrow(legenda) == 0) {
    stop("Legenda de ", tema, " vazia. Confira o filtro e os scripts de legenda em data-raw/.")
  }
  if (anyDuplicated(legenda$class_id)) {
    stop("Legenda de ", tema, " com class_id repetido (ex.: mais de uma coleção).")
  }

  invisible(legenda)
}
