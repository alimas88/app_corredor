#' The application server-side
#'
#' @param input,output,session Internal parameters for {shiny}.
#'     DO NOT REMOVE.
#' @import shiny
#' @importFrom odbc odbc
#' @noRd
app_server <- function(input, output, session) {

  # Área de estudo enviada pelo usuário (NULL enquanto não houver envio válido)
  area_estudo <- mod_corredor_server("corredor")

  # Registro central dos resultados + módulo de exportação única em xlsx
  registro <- registro_criar()
  mod_exportar_server("exportar", registro)

  # faz a conexão ao banco de dados (parâmetros no golem-config.yml).
  # Sem conexão, os temas do BD ficam "não verificados", sem derrubar a sessão.
  con <- tryCatch(conectar_bd(), error = function(e) {
    showNotification(paste('Erro ao conectar ao Banco de Dados:', e$message),
                     type = 'error', duration = 10)
    NULL
  })

  if (is.null(con)) {
    showNotification('Os temas que dependem do Banco de Dados ficarão não verificados.',
                     type = 'warning', duration = 10)
  } else {
    # Finaliza a conexão ao banco de dados quando a sessão terminar
    session$onSessionEnded(function() DBI::dbDisconnect(con))
  }

  # Um mod_tema_server por tema do catálogo (golem-config.yml, seção temas).
  # O módulo é criado uma vez e refaz a verificação sempre que a área de estudo
  # muda. A ordem do catálogo é a ordem dos temas na planilha de conferência.
  purrr::walk(catalogo_temas(), function(tema) {
    mod_tema_server(tema$chave, area_estudo,
                    consulta = consulta_tema(tema, con),
                    tema = tema$nome,
                    registro = registro,
                    colunas = tema$colunas)
  })

}
