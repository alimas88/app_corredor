#' query_bd
#'
#' @description Retorna query com as colunas ordenadas. Download dados geográficos filtrados.
#'
#' @param con Conexão ao BD
#'
#' @param tabela String Nome da tabela no BD
#'
#' @importFrom glue glue
#'
#' @return character
#'
#' @noRd
query_bd <- function(con, tabela, filtro_bbox) {


  query_info_coluna <- glue::glue("SELECT COLUMN_NAME, CHARACTER_MAXIMUM_LENGTH ",
                                  "FROM INFORMATION_SCHEMA.COLUMNS ",
                                  "WHERE TABLE_NAME = '{tabela}'")

  info_colunas <- DBI::dbGetQuery(con, query_info_coluna)

  coluna_final <- info_colunas %>%
    dplyr::filter(CHARACTER_MAXIMUM_LENGTH == -1) %>%
    dplyr::pull(COLUMN_NAME)
  coluna_final

  coluna_inicio <- info_colunas %>%
    dplyr::filter(CHARACTER_MAXIMUM_LENGTH != -1) %>%
    dplyr::pull(COLUMN_NAME)
  coluna_inicio

  coluna_ordenada <- c(coluna_inicio, coluna_final) %>%
    paste(collapse = ', ')

  query_banco <- glue::glue("SELECT {coluna_ordenada}, Shape.STAsText() AS wkt ",
                            "FROM {tabela} ",
                            "WHERE Shape.STIntersects(geometry::STGeomFromText('", filtro_bbox, "', 4674)) = 1;")

  return(query_banco)

}
