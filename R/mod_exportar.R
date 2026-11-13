#' exportar UI Function
#'
#' @description Botão de download do xlsx com todos os resultados.
#'
#' @param id Identificador do módulo.
#'
#' @importFrom shiny NS downloadButton
#' @noRd
mod_exportar_ui <- function(id) {
  ns <- NS(id)
  downloadButton(ns("baixar_xlsx"), "Exportar resultados (.xlsx)",
                 class = "btn-success btn-sm")
}

#' exportar Server Functions
#'
#' @param id Identificador do módulo.
#' @param registro reactiveVal criado por `registro_criar()`.
#'
#' @noRd
mod_exportar_server <- function(id, registro) {
  moduleServer(id, function(input, output, session) {

    output$baixar_xlsx <- downloadHandler(

      filename = function() {
        paste0("analise_corredor_", format(Sys.time(), "%Y%m%d_%H%M"), ".xlsx")
      },

      content = function(file) {

        resultados <- coletar_resultados(registro)

        if (length(resultados) == 0) {
          showNotification(
            "Nenhum resultado disponível. Carregue um corredor primeiro.",
            type = "warning"
          )
        }

        escrever_xlsx(resultados, file)
      }
    )
  })
}
