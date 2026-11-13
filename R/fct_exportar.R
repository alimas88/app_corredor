#' Avalia os reactives do registro
#'
#' @description Executa cada reactive registrado. Os que falharem (por exemplo,
#' `req()` sem corredor) são ignorados. Geometrias são removidas. Os reactives
#' são avaliados com `isolate()`, então a função também roda fora de um
#' contexto reativo (ex.: nos testes).
#'
#' @param registro reactiveVal criado por `registro_criar()`.
#'
#' @return lista nomeada de tibbles
#' @noRd
coletar_resultados <- function(registro) {

  shiny::isolate(registro()) %>%
    purrr::map(~ tryCatch(shiny::isolate(.x()), error = function(e) NULL)) %>%
    purrr::compact() %>%
    purrr::map(preparar_aba)
}

#' Prepara um resultado para exportação em xlsx
#'
#' @description Remove a geometria e converte list-columns em texto,
#' pois o xlsx não aceita colunas do tipo lista.
#'
#' @param dados data.frame ou sf.
#'
#' @return tibble
#' @noRd
preparar_aba <- function(dados) {

  dados %>%
    sf::st_drop_geometry() %>%
    dplyr::as_tibble() %>%
    dplyr::mutate(dplyr::across(
      dplyr::where(is.list),
      ~ purrr::map_chr(.x, ~ paste(format(.x), collapse = "; "))
    ))
}

#' Nomes válidos para abas do Excel
#'
#' @description Máximo de 31 caracteres, sem os caracteres `[ ] : * ? / \`
#' e sem repetição. Trunca em 28 para deixar espaço ao sufixo de unicidade.
#'
#' @param nomes character
#'
#' @return character
#' @noRd
nomes_abas_validos <- function(nomes) {

  nomes <- nomes |>
    stringr::str_replace_all("[\\[\\]:*?/\\\\]", " ") |>
    stringr::str_squish() |>
    stringr::str_trunc(28, ellipsis = "")

  nomes[nomes == ""] <- "Aba"
  make.unique(nomes, sep = "_")
}

#' Escreve o xlsx final
#'
#' @description Um único arquivo com a aba "Resumo" e uma aba por resultado.
#'
#' @param resultados lista nomeada de data.frames (saída de `coletar_resultados()`).
#' @param path caminho do arquivo .xlsx.
#'
#' @return path (invisível)
#' @noRd
escrever_xlsx <- function(resultados, path) {

  nomes <- nomes_abas_validos(names(resultados))
  resultados <- stats::setNames(resultados, nomes)

  resumo <- dplyr::tibble(
    Aba = nomes,
    Registros = purrr::map_int(resultados, nrow)
  )

  writexl::write_xlsx(c(list(Resumo = resumo), resultados), path = path)
}
