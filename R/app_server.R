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

  # Cada tema é um mod_tema_server: o módulo é criado uma vez e refaz a
  # verificação sempre que a área de estudo muda. A ordem das chamadas é a
  # ordem dos temas na planilha de conferência.

  # tema vetorial do BD: id do módulo, chave no golem-config.yml e nome do tema
  tema_bd <- function(id, chave, tema, filtro_row = NULL) {
    tabela <- tabela_tema(chave)
    force(filtro_row)
    mod_tema_server(id, area_estudo, tema = tema, registro = registro,
                    consulta = \(area) consultar_tema_bd(con, tabela, area, filtro_row))
  }

  # raster de classes em tiles no BD (ver data-raw/carga_mapbiomas_col11_2025.R)
  tema_raster_bd <- function(id, chave, tema, legenda, ...) {
    tabela <- tabela_tema(chave)
    validar_legenda(legenda, tema)
    mod_tema_server(id, area_estudo, tema = tema, registro = registro,
                    consulta = \(area) resumir_raster_bd(con, tabela, area, legenda, ...))
  }

  # INFRAESTRUTURA ------------------------------------------------------------

  tema_bd('infra_municipio', 'municipios', 'Municípios')
  tema_bd('infra_area_urbana', 'areas_urbanas', 'Áreas Urbanas')
  tema_bd('infra_lt', 'linhas_transmissao', 'Linhas de Transmissão',
          filtro_row = filtro_config('filtro_linhas_transmissao'))
  tema_bd('subestacao', 'subestacoes', 'Subestações')
  tema_bd('usinas', 'usinas', 'Usinas')
  tema_bd('gasoduto_transporte', 'gasoduto_transporte', 'Gasoduto Transporte')
  tema_bd('duto_escoamento', 'duto_escoamento', 'Dutos Escoamento')
  tema_bd('gasoduto_distribuicao', 'gasoduto_distribuicao', 'Gasoduto Distribuição')
  tema_bd('transportes_rodovias', 'rodovias', 'Rodovias')
  tema_bd('transportes_aerodromos', 'aerodromos', 'Aeródromos')
  tema_bd('transportes_ferrovias', 'ferrovias', 'Ferrovias')


  # USO DO SOLO ---------------------------------------------------------------
  # A coleção da legenda deve ser a mesma do raster da tabela.
  tema_raster_bd('mapbiomas', 'mapbiomas', 'MapBiomas',
                 legenda = legenda_mapbiomas |>
                   dplyr::filter(colecao == get_golem_config('mapbiomas_colecao')) |>
                   dplyr::select(class_id, descricao, color))


  # MEIO FÍSICO ---------------------------------------------------------------
  # Último tema lido de arquivo, até ganhar view no BD.
  hidrografia <- get_golem_config('hidrografia')
  mod_tema_server('curso_agua', area_estudo, tema = 'Hidrografia', registro = registro,
                  consulta = \(area) ler_tema_arquivo(hidrografia$gdb, hidrografia$layer, area))

  tema_bd('caverna', 'cavernas', 'Cavernas')

  # Sempre as 6 classes, de Plano a Escarpado, com a faixa em % de cada uma.
  tema_raster_bd('declividade', 'declividade', 'Declividade',
                 legenda = legenda_declividade |>
                   dplyr::mutate(faixa = dplyr::if_else(
                     is.na(lim_sup),
                     paste0('> ', lim_inf, '%'),
                     paste0(lim_inf, ' a ', lim_sup, '%')
                   )) |>
                   dplyr::select(class_id, descricao, faixa, color),
                 ordem = 'classe', todas_classes = TRUE)

  # PROCESSOS MINERÁRIOS ------------------------------------------------------
  tema_bd('pm', 'processos_minerarios', 'Processos Minerários')

  # ÁREAS PROTEGIDAS ----------------------------------------------------------
  tema_bd('terra_indigena', 'terras_indigenas', 'Terras Indígenas')
  tema_bd('terra_quilombola', 'terras_quilombolas', 'Terras Quilombolas')
  tema_bd('projeto_assentamento', 'assentamentos', 'Projetos de Assentamento')
  tema_bd('uc', 'uc', 'Unidades de Conservação')
  tema_bd('uc_complementar', 'uc_complementar', 'UC Complementar')
  tema_bd('rppn', 'rppn', 'RPPN')
  tema_bd('sitios_arqueologicos', 'sitios_arqueologicos', 'Sítios Arqueológicos')

}
