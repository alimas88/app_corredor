#' infra UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
#' @importFrom dplyr filter select
#' @importFrom DT DTOutput
#' @importFrom sf st_read st_filter st_intersects
#'
mod_sobreposicao_ui <- function(id) {
  ns <- NS(id)
  tagList(
    DT::DTOutput(ns('tabela_sobreposicao'))
  )
}

#' infra Server Functions
#'
#' @param registro reactiveVal criado por `registro_criar()`. Opcional.
#' @param aba Nome da aba no xlsx exportado. Padrão: o próprio `id`.
#'
#' @importFrom DT renderDT
#' @noRd
mod_sobreposicao_server <- function(id, shp_corredor, gdb_tema, layer, filtro_bbox = NULL,
                                    filtro_col = NULL, filtro_row = NULL,
                                    registro = NULL, aba = id){
  moduleServer(id, function(input, output, session){

    # Lê a base no GDB (filtrada pelo bbox, se houver).
    # Força a validade da geometria (há bases com polígonos inválidos).
    # Se a pasta/layer não estiver acessível, avisa e segue com NULL,
    # sem derrubar a sessão.
    base_tema <- tryCatch({
      sf::st_read(gdb_tema, layer = layer,
                  wkt_filter = if (is.null(filtro_bbox)) character(0) else filtro_bbox,
                  quiet = TRUE) %>%
        sf::st_make_valid()
    }, error = function(e) {
      showNotification(
        paste("Erro ao carregar", layer, ":", conditionMessage(e)),
        type = "error",
        duration = 10
      )
      NULL
    })

    # filtro opcional de linhas (ex.: retirar feições inativas)
    if (!is.null(base_tema) && !is.null(filtro_row)){
      base_tema <- base_tema %>% dplyr::filter(!!filtro_row)
    }

    if (!is.null(base_tema) && !is.null(filtro_col)){
      base_tema <- base_tema %>% dplyr::select(dplyr::all_of(filtro_col))
    }

    # intersecta o tema com o corredor
    tema_corredor <- reactive({

      req(shp_corredor())
      validate(need(!is.null(base_tema),
                    paste("Tema indisponível:", layer, "não pôde ser carregado.")))
      sf::st_filter(base_tema, shp_corredor(), .predicate = sf::st_intersects)
    })

    # Disponibiliza o resultado para a exportação única em xlsx
    registro_adicionar(registro, aba, tema_corredor)

    print(glue::glue("{id} - Processamento Finalizado!"))

    # Renderiza a tabela com as feições sobrepostas ao corredor
    output$tabela_sobreposicao <- DT::renderDT({
      tema_corredor() %>%
        sf::st_drop_geometry() %>%
        dplyr::as_tibble() %>%
        tabela_dt()
    }, server = FALSE)

  })
}

## To be copied in the UI
# mod_infra_ui("infra_1")

## To be copied in the server
# mod_infra_server("infra_1")
