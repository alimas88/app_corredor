#' The application User-Interface
#'
#' @param request Internal parameter for `{shiny}`.
#'     DO NOT REMOVE.
#' @import shiny
#' @import shinydashboard
#' @noRd
app_ui <- function(request) {

  catalogo <- catalogo_temas()
  grupos <- unique(purrr::map_chr(catalogo, "grupo"))

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
      # Um item de menu por grupo do catálogo de temas (golem-config.yml)
      dashboardSidebar(
        do.call(sidebarMenu, c(
          list(menuItem('Corredor', tabName = 'painel_corredor')),
          purrr::map(grupos, \(g) menuItem(g, tabName = id_grupo(g)))
        ))
      ),
      dashboardBody(
        do.call(tabItems, c(
          list(tabItem(tabName = 'painel_corredor', mod_corredor_ui("corredor"))),
          purrr::map(grupos, \(g) pagina_grupo(g, catalogo))
        ))
      )
    )
  )
}

#' Página de um grupo de temas
#'
#' @description Uma caixa (`tabBox`) por subgrupo, com uma aba por tema, na
#' ordem do catálogo.
#'
#' @param grupo String. Grupo do catálogo.
#' @param catalogo Saída de `catalogo_temas()`.
#' @noRd
pagina_grupo <- function(grupo, catalogo) {

  temas <- purrr::keep(catalogo, \(t) t$grupo == grupo)
  subgrupos <- unique(purrr::map_chr(temas, "subgrupo"))

  caixas <- purrr::map(subgrupos, function(sg) {
    abas <- temas |>
      purrr::keep(\(t) t$subgrupo == sg) |>
      purrr::map(\(t) tabPanel(t$nome, mod_tema_ui(t$chave))) |>
      unname()
    do.call(tabBox, c(list(title = sg, width = 12), abas))
  })

  tabItem(tabName = id_grupo(grupo), do.call(fluidPage, unname(caixas)))
}

#' Identificador do grupo para o menu (ex.: "Meio Físico" -> "meio_fisico")
#' @noRd
id_grupo <- function(grupo) {
  grupo |>
    stringi::stri_trans_general("Latin-ASCII") |>
    tolower() |>
    stringr::str_replace_all("[^a-z0-9]+", "_")
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
