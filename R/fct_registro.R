#' Cria o registro de resultados
#'
#' @description Cria um `reactiveVal` que guarda uma lista ordenada de reactives,
#' um por tabela de resultado. É criado uma única vez em `app_server()`.
#'
#' @return reactiveVal
#' @noRd
registro_criar <- function() {
  shiny::reactiveVal(list())
}

#' Registra (ou substitui) o resultado de um módulo
#'
#' @param registro reactiveVal criado por `registro_criar()`. Se NULL, nada é feito.
#' @param aba String. Nome da aba no xlsx.
#' @param dados reactive que devolve um data.frame ou sf.
#'
#' @return NULL (invisível)
#' @noRd
registro_adicionar <- function(registro, aba, dados) {

  if (is.null(registro)) return(invisible(NULL))
  stopifnot(shiny::is.reactive(dados))

  lista <- shiny::isolate(registro())
  lista[[aba]] <- dados   # se a aba já existe, substitui mantendo a posição
  registro(lista)

  invisible(NULL)
}
