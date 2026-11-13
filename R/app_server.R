#' The application server-side
#'
#' @param input,output,session Internal parameters for {shiny}.
#'     DO NOT REMOVE.
#' @import shiny
#' @importFrom odbc odbc
#' @noRd
app_server <- function(input, output, session) {

  # Inicializa o módulo Corredor e obtém o shapefile carregado
  shp_corredor <- mod_corredor_server("corredor")

  # Registro central dos resultados + módulo de exportação única em xlsx
  registro <- registro_criar()
  mod_exportar_server("exportar", registro)

  # faz a conexão ao banco de dados (parâmetros no golem-config.yml).
  # Envia mensagem em caso de erro.
  con <- tryCatch({

    conectar_bd()

  }, error = function(e){
    showNotification(paste('Erro ao conectar ao Banco de Dados:', e$message),
                     type = 'error',
                     duration = 10)
    return(NULL)
  })

  # se a conexão for NULL avise ao usuário sem interromper o processamento.
  if (is.null(con)){

    showNotification('Funcionalidades que dependam do Banco de Dados ficarão indisponíveis.',
                     type = 'warning',
                     duration = 10)
  } else {

    # Finaliza a conexão ao banco de dados quando a sessão terminar
    session$onSessionEnded(function() {
      if (!is.null(con)) {
        DBI::dbDisconnect(con)
      }
    })

  }


  # aguardar o corredor ser carregado para fazer os calculos
  observeEvent(shp_corredor(), {

    # limpa os resultados de um corredor carregado anteriormente
    registro(list())

    # criar um filtro de sql a partir do bbox para reduzir a resposta do BD
    filtro_bbox <- sf::st_as_text(sf::st_as_sfc(sf::st_bbox(shp_corredor())))

    # temas vetoriais lidos do BD: id do módulo, chave no golem-config.yml e aba
    tema_bd <- function(id, chave, aba, filtro_row = NULL) {
      mod_banco_server(id, con = con, shp_corredor,
                       tabela = tabela_tema(chave),
                       filtro_bbox = filtro_bbox,
                       filtro_row = filtro_row,
                       registro = registro, aba = aba)
    }

    # INFRAESTRUTURA ----------------------------------------------------------

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


    # USO DO SOLO -------------------------------------------------------------
    # raster lido do BD, em tiles GeoTIFF (ver data-raw/carga_mapbiomas_col11_2025.R)
    # A coleção da legenda deve ser a mesma do raster da `tabela`.
    mod_raster_bd_server('mapbiomas', con = con, shp_corredor,
                         tabela = tabela_tema('mapbiomas'),
                         legenda = legenda_mapbiomas |>
                           dplyr::filter(colecao == get_golem_config('mapbiomas_colecao')) |>
                           dplyr::select(class_id, descricao, color),
                         tema = 'MapBiomas',
                         registro = registro, aba = 'MapBiomas')


    # MEIO FÍSICO -------------------------------------------------------------
    # Último tema lido de arquivo (mod_sobreposicao), até ganhar tabela no BD.
    hidrografia <- get_golem_config('hidrografia')
    mod_sobreposicao_server('curso_agua', shp_corredor,
                            gdb_tema = hidrografia$gdb,
                            layer = hidrografia$layer,
                            filtro_bbox = filtro_bbox,
                            registro = registro, aba = 'Hidrografia')

    tema_bd('caverna', 'cavernas', 'Cavernas')

    # raster lido do BD, em tiles GeoTIFF
    # Sempre as 6 classes, de Plano a Escarpado, com a faixa em % de cada uma.
    mod_raster_bd_server('declividade', con = con, shp_corredor,
                         tabela = tabela_tema('declividade'),
                         legenda = legenda_declividade |>
                           dplyr::mutate(faixa = dplyr::if_else(
                             is.na(lim_sup),
                             paste0('> ', lim_inf, '%'),
                             paste0(lim_inf, ' a ', lim_sup, '%')
                           )) |>
                           dplyr::select(class_id, descricao, faixa, color),
                         tema = 'Declividade',
                         ordem = 'classe', todas_classes = TRUE,
                         registro = registro, aba = 'Declividade')

    # PROCESSOS MINERÁRIOS ----------------------------------------------------
    tema_bd('pm', 'processos_minerarios', 'Processos Minerários')

    # ÁREAS PROTEGIDAS --------------------------------------------------------
    tema_bd('terra_indigena', 'terras_indigenas', 'Terras Indígenas')
    tema_bd('terra_quilombola', 'terras_quilombolas', 'Terras Quilombolas')
    tema_bd('projeto_assentamento', 'assentamentos', 'Projetos de Assentamento')
    tema_bd('uc', 'uc', 'Unidades de Conservação')
    tema_bd('uc_complementar', 'uc_complementar', 'UC Complementar')
    tema_bd('rppn', 'rppn', 'RPPN')
    tema_bd('sitios_arqueologicos', 'sitios_arqueologicos', 'Sítios Arqueológicos')

  })

}
