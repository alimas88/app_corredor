#' banco UI Function
#'
#' @description A shiny Module.
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
mod_banco_ui <- function(id) {
  ns <- NS(id)
  tagList(

    DT::DTOutput(ns('tabela_sobreposicao'))

  )
}

#' banco Server Functions
#'
#' @param registro reactiveVal criado por `registro_criar()`. Opcional.
#' @param aba Nome da aba no xlsx exportado. Padrão: o próprio `id`.
#'
#' @noRd
mod_banco_server <- function(id, con, shp_corredor, tabela, filtro_bbox,
                             filtro_row = NULL, registro = NULL, aba = id){
  moduleServer(id, function(input, output, session){


    # Retorna NULL imediatamente se não houver conexão
    if (is.null(con)) {
      showNotification("Conexão com o banco de dados não está disponível.", type = "error", duration = 10)
      return(NULL)
    }

    # Tenta consultar e carregar os dados do banco
    base_tema <- tryCatch({

      query_tema <- glue::glue(
        "SELECT *, ",
        "Shape.STAsText() AS wkt ",
        "FROM {tabela} ",
        "WHERE Shape.STIntersects(",
        "geometry::STGeomFromText('{filtro_bbox}', 4674)",
        ") = 1;"
      )

      DBI::dbGetQuery(conn = con, statement = query_tema) %>%
        dplyr::mutate(Shape = sf::st_as_sfc(wkt, crs = 4674)) %>%
        dplyr::select(-dplyr::any_of(c("wkt", "GDB_GEOMATTR_DATA"))) %>%
        sf::st_as_sf()

    }, error = function(e) {
      showNotification(
        paste("Erro ao carregar dados de", tabela, ":", e$message),
        type = "error",
        duration = 10
      )
      return(NULL)
    })

    # filtro opcional de linhas (ex.: retirar feições inativas)
    # (só aplica se a consulta ao banco não falhou)
    if (!is.null(filtro_row) && !is.null(base_tema)){
      base_tema <- base_tema %>% dplyr::filter(!!filtro_row)
    }

    # Interseção com o corredor. O filtro usa o GEOS (s2 desligado só aqui):
    # o s2 rejeita alguns polígonos que são válidos pelas regras OGC.
    tema_corredor <- reactive({
      req(shp_corredor(), !is.null(base_tema))
      s2_antes <- sf::sf_use_s2(FALSE)
      on.exit(sf::sf_use_s2(s2_antes), add = TRUE)
      sf::st_filter(base_tema, shp_corredor(), .predicate = sf::st_intersects)
    })

    # Disponibiliza o resultado para a exportação única em xlsx
    registro_adicionar(registro, aba, tema_corredor)

    # Renderiza a tabela
    output$tabela_sobreposicao <- DT::renderDT({
      req(tema_corredor())
      tema_corredor() %>%
        sf::st_drop_geometry() %>%
        dplyr::as_tibble() %>%
        tabela_dt()
    }, server = FALSE)

  })
}

## To be copied in the UI
# mod_banco_ui("banco_1")

## To be copied in the server
# mod_banco_server("banco_1")
