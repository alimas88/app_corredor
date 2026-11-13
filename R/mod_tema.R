#' tema UI Function
#'
#' @description Tabela de resultado de um tema.
#'
#' @param id Identificador do módulo.
#'
#' @noRd
#' @importFrom shiny NS
mod_tema_ui <- function(id) {
  DT::DTOutput(NS(id, "tabela"))
}

#' tema Server Functions
#'
#' @description Verifica um tema sempre que a área de estudo muda e mostra a
#' tabela de resultado. Serve para qualquer tema: o que muda entre eles é só a
#' `consulta` (ver `consultar_tema_bd()`, `resumir_raster_bd()` e
#' `ler_tema_arquivo()`).
#'
#' A verificação roda assim que a área de estudo chega, mesmo com a aba do tema
#' fechada. Se a consulta falhar, o tema fica "não verificado": a tabela mostra
#' o motivo e um aviso aparece na tela (menos quando falta a conexão ao banco,
#' que o app já avisa uma única vez).
#'
#' @param id Identificador do módulo.
#' @param area reactive com a área de estudo (sf). NULL enquanto não houver.
#' @param consulta Função de um argumento (a área de estudo) que devolve a
#'   tabela de resultado (data.frame ou sf).
#' @param tema String. Nome do tema, usado nas mensagens, na planilha de
#'   conferência e no registro.
#' @param registro reactiveVal criado por `registro_criar()`. Opcional.
#'
#' @return reactive com o `resultado_tema`.
#' @noRd
mod_tema_server <- function(id, area, consulta, tema, registro = NULL) {

  stopifnot(is.function(consulta))

  moduleServer(id, function(input, output, session) {

    resultado <- reactive({
      req(area())
      verificar_tema(\() consulta(area()))
    })

    registro_adicionar(registro, tema, resultado)

    # força a verificação mesmo com a aba fechada e avisa as falhas
    observeEvent(resultado(), {
      r <- resultado()
      if (r$situacao == SITUACAO[["nao_verificado"]] && r$notificar) {
        showNotification(paste0("Tema não verificado (", tema, "): ", r$erro),
                         type = "error", duration = 10)
      }
    })

    output$tabela <- DT::renderDT({
      r <- resultado()
      validate(need(r$situacao != SITUACAO[["nao_verificado"]],
                    paste0("Tema não verificado: ", r$erro)))
      tabela_dt(preparar_aba(r$dados))
    }, server = FALSE)

    resultado
  })
}
