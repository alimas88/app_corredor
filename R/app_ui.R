#' The application User-Interface
#'
#' @param request Internal parameter for `{shiny}`.
#'     DO NOT REMOVE.
#' @import shiny
#' @import shinydashboard
#' @noRd
app_ui <- function(request) {
  tagList(
    # Leave this function for adding external resources
    golem_add_external_resources(),
    # Your application UI logic
    dashboardPage(
      dashboardHeader(
        title = span(" "),
        # botão de exportação única (xlsx com uma aba por tabela)
        tags$li(class = "dropdown",
                style = "padding: 8px 15px;",
                mod_exportar_ui("exportar"))
      ),
      dashboardSidebar(
        sidebarMenu(
          menuItem('Corredor', tabName = 'painel_corredor'),
          menuItem('Infraestrutura', tabName = 'infra'),
          menuItem('Uso do Solo', tabName = 'uso_do_solo'),
          menuItem('Meio Físico', tabName = 'meio_fisico'),
          menuItem('Processos Minerários', tabName = 'processos_minerarios'),
          menuItem('Áreas Protegidas', tabName = 'areas_protegidas')

        )
      ),
      dashboardBody(
        tabItems(
          tabItem(tabName = 'painel_corredor', mod_corredor_ui("corredor")),

          # UI para INFRAESTRUTURA
          tabItem(tabName = 'infra',
                  fluidPage(
                    tabBox(
                      title = 'Político/Administrativo', width = 12,
                      tabPanel('Municípios', mod_banco_ui('infra_municipio')),
                      tabPanel('Áreas Urbanas', mod_banco_ui('infra_area_urbana'))
                    ),

                    tabBox(
                      title = 'Transmissão', width = 12,
                      tabPanel('Linhas de Transmissão', mod_banco_ui('infra_lt')),
                      tabPanel('Subestações', mod_banco_ui('subestacao'))
                    ),

                    tabBox(
                      title = 'Geração', width = 12,
                      tabPanel('Usinas', mod_banco_ui('usinas'))
                    ),

                    tabBox(
                      title = 'Dutos', width = 12,
                      tabPanel('Gasoduto Transporte', mod_banco_ui('gasoduto_transporte')),
                      tabPanel('Dutos Escoamento', mod_banco_ui('duto_escoamento')),
                      tabPanel('Gasoduto Distribuição', mod_banco_ui('gasoduto_distribuicao'))
                    ),

                    tabBox(
                      title = 'Transportes', width = 12,
                      tabPanel('Rodovias', mod_banco_ui('transportes_rodovias')),
                      tabPanel('Aeródromos', mod_banco_ui('transportes_aerodromos')),
                      tabPanel('Ferrovias', mod_banco_ui('transportes_ferrovias'))
                    )
                  )
          ),


          # UI para USO DO SOLO
          tabItem(tabName = 'uso_do_solo',
                  fluidPage(
                    tabBox(
                      title = 'Uso do Solo', width = 12,
                      tabPanel('MapBiomas', mod_raster_bd_ui('mapbiomas'))
                    )
                  )
          ),


          # UI para MEIO FÍSICO
          tabItem(tabName = 'meio_fisico',
                  fluidPage(
                    tabBox(
                      title = 'Meio Físico', width = 12,
                      tabPanel("Hidrografia", mod_sobreposicao_ui('curso_agua')),
                      tabPanel('Cavernas', mod_banco_ui('caverna')),
                      tabPanel('Declividade', mod_raster_bd_ui('declividade'))
                    )
                  )
          ),


          # UI para PROCESSOS MINERÁRIOS
          tabItem(tabName = 'processos_minerarios',
                  fluidPage(
                    tabBox(
                      title = 'Processos Minerários', width = 12,
                      tabPanel('Processos Minerários', mod_banco_ui('pm'))
                    )
                  )
          ),


          # UI para ÁREAS PROTEGIDAS
          tabItem(tabName = 'areas_protegidas',
                  fluidPage(
                    tabBox(
                      title = 'Áreas Protegidas', width = 12,
                      tabPanel('Terras Indígenas', mod_banco_ui('terra_indigena')),
                      tabPanel('Terras Quilombolas', mod_banco_ui('terra_quilombola')),
                      tabPanel('Projetos de Assentamento', mod_banco_ui('projeto_assentamento')),
                      tabPanel('Unidades de Conservação', mod_banco_ui('uc')),
                      tabPanel('UC Complementar', mod_banco_ui('uc_complementar')),
                      tabPanel('RPPN', mod_banco_ui('rppn')),
                      tabPanel('Sítios Arqueológicos', mod_banco_ui('sitios_arqueologicos'))
                    )
                  )
          )

        )
      )
    )
  )
}

#' Add external Resources to the Application
#'
#' This function is internally used to add external
#' resources inside the Shiny application.
#'
#' @import shiny
#' @importFrom golem add_resource_path activate_js favicon bundle_resources
#' @noRd
golem_add_external_resources <- function() {
  add_resource_path(
    "www",
    app_sys("app/www")
  )

  tags$head(
    tags$link(rel = 'stylesheet', type = 'text/css', href = 'www/style.css'),
    favicon(),
    bundle_resources(
      path = app_sys("app/www"),
      app_title = "analise.corredor"
    )
    # Add here other external resources
    # for example, you can add shinyalert::useShinyalert()
  )
}
