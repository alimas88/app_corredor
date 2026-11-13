#' Avalia os reactives do registro
#'
#' @description Executa cada reactive registrado e devolve o resultado de cada
#' tema. Os que param no `req()` (ainda sem área de estudo) são ignorados.
#' Qualquer outro erro vira "não verificado", para que o tema não suma da
#' planilha de conferência. Os reactives são avaliados com `isolate()`, então a
#' função também roda fora de um contexto reativo (ex.: nos testes).
#'
#' @param registro reactiveVal criado por `registro_criar()`.
#'
#' @return lista nomeada (pelo tema) de `resultado_tema`.
#' @noRd
coletar_resultados <- function(registro) {

  shiny::isolate(registro()) |>
    purrr::map(\(r) tryCatch(
      shiny::isolate(r()),
      shiny.silent.error = function(e) NULL,
      error = function(e) resultado_tema(erro = e)
    )) |>
    purrr::compact()
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

  dados |>
    sf::st_drop_geometry() |>
    dplyr::as_tibble() |>
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

#' Escreve a planilha de conferência
#'
#' @description Um único arquivo com a aba "Resumo" e uma aba por tema
#' verificado. O "Resumo" traz a situação de todos os temas, com os não
#' verificados no topo e o motivo da falha. Tema não verificado não tem aba.
#'
#' @param resultados lista nomeada de `resultado_tema` (saída de
#'   `coletar_resultados()`).
#' @param path caminho do arquivo .xlsx.
#'
#' @return path (invisível)
#' @noRd
escrever_xlsx <- function(resultados, path) {

  situacao <- purrr::map_chr(resultados, "situacao")
  verificado <- situacao != SITUACAO[["nao_verificado"]]

  # "Resumo" entra na lista só para não haver aba de tema com o mesmo nome
  nomes_abas <- nomes_abas_validos(c("Resumo", rlang::names2(resultados)[verificado]))[-1]

  abas <- resultados[verificado] |>
    purrr::map(\(r) preparar_aba(r$dados)) |>
    stats::setNames(nomes_abas)

  aba <- rep(NA_character_, length(resultados))
  aba[verificado] <- nomes_abas

  resumo <- dplyr::tibble(
    Tema = rlang::names2(resultados),
    `Situação` = unname(situacao),
    Registros = purrr::map_int(resultados, \(r) if (is.null(r$dados)) NA_integer_ else nrow(r$dados)),
    Aba = aba,
    `Observação` = purrr::map_chr(resultados, \(r) if (is.null(r$erro)) NA_character_ else r$erro)
  ) |>
    dplyr::arrange(`Situação` != SITUACAO[["nao_verificado"]])

  writexl::write_xlsx(c(list(Resumo = resumo), abas), path = path)
}
