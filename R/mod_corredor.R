
# Módulo Corredor - UI

#' Módulo Corredor
#'
#' @param id Identificador único para o namespace.
#'
#' @import leaflet
#' @return sf
#'
#' @noRd
mod_corredor_ui <- function(id){

  ns <- NS(id)
  tagList(
    fileInput(ns('corredor'), 'Selecione o arquivo .zip contendo o shapefile do corredor. No mínimo arquivos .shp, .dbf, .shx e .prj',
              multiple = FALSE, accept = c('.zip')),
    # mensagem de erro do último envio (vazia quando o envio deu certo)
    uiOutput(ns('mensagem')),
    leafletOutput(ns('map_corredor'), height = 500)
  )

}

# Módulo Corredor - Server

mod_corredor_server <- function(id){

  moduleServer(id, function(input, output, session){

    corredor <- reactiveVal(NULL)
    mensagem <- reactiveVal(NULL)

    # Cada envio substitui o corredor e a mensagem anteriores.
    # Um envio inválido descarta o corredor anterior: o mapa volta ao Brasil e
    # os temas ficam vazios até o próximo envio válido.
    observeEvent(input$corredor, {

      lido <- tryCatch(
        list(sf = ler_corredor(input$corredor$datapath, input$corredor$name),
             erro = NULL),
        # problemas previstos no arquivo (ver ler_corredor())
        erro_corredor = function(e) list(sf = NULL, erro = conditionMessage(e)),
        # qualquer outro erro: não derruba a sessão
        error = function(e) list(sf = NULL,
                                 erro = paste("Não foi possível ler o arquivo:",
                                              conditionMessage(e)))
      )

      corredor(lido$sf)
      mensagem(lido$erro)
    })

    output$mensagem <- renderUI({
      req(mensagem())
      div(class = 'alert alert-danger', role = 'alert',
          strong('Arquivo não carregado. '), mensagem())
    })

    # O mapa nunca recebe erro: Brasil sem corredor, o polígono com corredor.
    output$map_corredor <- renderLeaflet({

      mapa <- leaflet() %>%
        addProviderTiles(providers$Esri.WorldTopoMap, group = "Topográfico") %>%
        addProviderTiles(providers$Esri.WorldImagery, group = "Satélite") %>%
        addProviderTiles(providers$OpenStreetMap, group = "OpenStreetMap") %>%
        addLayersControl(
          baseGroups = c("Topográfico", "Satélite", "OpenStreetMap"),
          options = layersControlOptions(collapsed = TRUE))

      if (is.null(corredor())) {
        return(mapa %>% setView(lng = -54, lat = -15, zoom = 4))
      }

      mapa %>%
        addPolygons(
          data = corredor(),
          color = 'black',
          weight = 2,
          fill = FALSE,
          opacity = 1)
    })

    # Retorna o corredor (somente leitura) para os outros módulos.
    # NULL enquanto não houver envio válido: os módulos dos temas param no req().
    return(reactive(corredor()))
  })
}
