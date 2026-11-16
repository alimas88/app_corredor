# utils para variáveis globais

if(getRversion() >= "2.15.1") {
  utils::globalVariables(c("wkt", "GDB_GEOMATTR_DATA", "class_id",
                           "legenda_mapbiomas", "level", "percentagem",
                           "n", "descricao", "color", "colecao",
                           "legenda_declividade", "lim_inf", "lim_sup", "faixa",
                           "COLUMN_NAME", "DATA_TYPE", "CHARACTER_MAXIMUM_LENGTH"))
}

#' Valor padrão para NULL (como o `%||%` do R >= 4.4 e do rlang)
#' @noRd
`%||%` <- function(x, y) if (is.null(x)) y else x
