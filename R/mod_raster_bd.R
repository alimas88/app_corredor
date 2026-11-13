#' raster_bd UI Function
#'
#' @description Tabela com o percentual da área de estudo por classe de um
#' raster gravado em tiles no BD (MapBiomas, declividade etc.).
#'
#' @param id,input,output,session Internal parameters for {shiny}.
#'
#' @noRd
#'
#' @importFrom shiny NS tagList
#' @import dplyr
mod_raster_bd_ui <- function(id) {
  ns <- NS(id)
  tagList(

    DT::DTOutput(ns('tabela_classes'))

  )
}

#' raster_bd Server Functions
#'
#' @description Calcula o percentual da área de estudo por classe de um raster
#' de classes. O raster é lido do SQL Server, em tiles (ver `contar_raster_bd()`).
#' O percentual é calculado sobre os pixels com dado: os pixels sem dado (mar
#' aberto, fora do Brasil) não entram no total.
#'
#' @param con Conexão DBI ao SQL Server. NULL se a conexão falhou.
#' @param shp_corredor reactive com a área de estudo (sf).
#' @param tabela String. Tabela de tiles do raster no BD.
#' @param legenda data.frame com as classes do raster da `tabela`. Colunas
#'   obrigatórias: `class_id` (valor do pixel), `descricao` e `color`. As demais
#'   colunas (ex.: `faixa`) são mostradas na tabela de resultado, depois de
#'   `descricao`. Passe só as colunas que devem aparecer.
#' @param tema String. Nome do tema, usado nas mensagens (ex.: "MapBiomas").
#' @param ordem Ordem das linhas: "percentagem" (decrescente) ou "classe" (a
#'   ordem das linhas da `legenda`).
#' @param todas_classes Se TRUE, a tabela traz todas as classes da `legenda`,
#'   com 0 nas que não ocorrem na área de estudo. Se FALSE, só as que ocorrem.
#' @param registro reactiveVal criado por `registro_criar()`. Opcional.
#' @param aba Nome da aba no xlsx exportado. Padrão: o `tema`.
#'
#' @noRd
mod_raster_bd_server <- function(id, con, shp_corredor, tabela, legenda, tema,
                                 ordem = c("percentagem", "classe"),
                                 todas_classes = FALSE,
                                 registro = NULL, aba = tema){

  ordem <- match.arg(ordem)

  # Uma legenda vazia ou incompleta impede o app de iniciar, com mensagem
  # (ex.: coleção do MapBiomas sem legenda no pacote).
  faltam <- setdiff(c("class_id", "descricao", "color"), names(legenda))
  if (length(faltam) > 0) {
    stop("Legenda de ", tema, " sem a(s) coluna(s): ", paste(faltam, collapse = ", "), ".")
  }
  if (nrow(legenda) == 0) {
    stop("Legenda de ", tema, " vazia. Confira o filtro e os scripts de legenda em data-raw/.")
  }
  if (anyDuplicated(legenda$class_id)) {
    stop("Legenda de ", tema, " com class_id repetido (ex.: mais de uma coleção).")
  }

  moduleServer(id, function(input, output, session){
    ns <- session$ns

    # percentual da área de estudo por classe do raster
    classes_corredor <- reactive({

      req(shp_corredor())
      validate(need(!is.null(con),
                    "Tema não verificado: banco de dados indisponível."))

      # Se a leitura falhar, avisa e segue com NULL, sem derrubar a sessão.
      contagem <- tryCatch(
        contar_raster_bd(con, tabela, shp_corredor()),
        error = function(e) {
          showNotification(
            paste0("Erro ao ler ", tema, " do banco de dados: ", conditionMessage(e)),
            type = "error",
            duration = 10
          )
          NULL
        }
      )

      validate(need(!is.null(contagem),
                    paste0("Tema não verificado: falha ao ler ", tema, " do banco de dados.")))
      validate(need(nrow(contagem) > 0,
                    paste0("A área de estudo não tem pixels de ", tema,
                           " (fora do Brasil ou em mar aberto).")))

      # classes da legenda que não ocorrem na área entram com 0
      if (todas_classes) {
        contagem <- legenda |>
          dplyr::select(class_id) |>
          dplyr::full_join(contagem, by = 'class_id') |>
          dplyr::mutate(n = dplyr::coalesce(n, 0))
      }

      # "classe": ordem da legenda; valores de pixel fora da legenda vão para o fim
      contagem <- switch(
        ordem,
        percentagem = dplyr::arrange(contagem, dplyr::desc(n)),
        classe      = dplyr::arrange(contagem, match(class_id, legenda$class_id), class_id)
      )

      contagem |>
        dplyr::mutate(percentagem = format(100 * n / sum(n), scientific = FALSE)) |>
        dplyr::left_join(legenda, by = 'class_id') |>
        dplyr::select(class_id, percentagem, descricao, dplyr::everything(), -n) |>
        dplyr::relocate(color, .after = dplyr::last_col())

    })

    # Disponibiliza o resultado para a exportação única em xlsx
    registro_adicionar(registro, aba, classes_corredor)

    output$tabela_classes <- DT::renderDT({

      tabela_dt(classes_corredor())

    }, server = FALSE)

  })
}

## To be copied in the UI
# mod_raster_bd_ui("raster_bd_1")

## To be copied in the server
# mod_raster_bd_server("raster_bd_1")
