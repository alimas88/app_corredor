#' Tabela DT padrão dos módulos de resultado
#'
#' @description Opções de DT compartilhadas pelos módulos. A exportação em
#' Excel é feita pelo botão global (`mod_exportar`); aqui só há o botão "copy".
#'
#' @param dados data.frame
#'
#' @return htmlwidget (DT)
#' @noRd
tabela_dt <- function(dados) {

  DT::datatable(
    dados,
    extensions = "Buttons",
    options = list(
      dom = "Bfrtip",
      scrollX = TRUE,
      buttons = list(
        list(extend = "copy",
             exportOptions = list(modifier = list(page = "all")))
      )
    )
  )
}
