#' Situações possíveis de um tema
#'
#' @description "Não verificado" (a consulta falhou) nunca equivale a "sem
#' interferência".
#' @noRd
SITUACAO <- c(
  com = "com interferência",
  sem = "sem interferência",
  nao_verificado = "não verificado"
)

#' Resultado da verificação de um tema
#'
#' @description Junta a situação do tema e a tabela de resultado. A situação
#' sai da tabela: com linhas, "com interferência"; sem linhas, "sem
#' interferência". Com erro, "não verificado", sem tabela.
#'
#' @param dados data.frame ou sf com as interferências. NULL quando há erro.
#' @param erro condition que impediu a verificação, ou NULL.
#'
#' @return Lista de classe `resultado_tema`, com `situacao`, `dados`, `erro`
#'   (mensagem) e `notificar` (FALSE quando o erro é a falta de conexão, que o
#'   app já avisa uma única vez).
#' @noRd
resultado_tema <- function(dados = NULL, erro = NULL) {

  if (!is.null(erro)) {
    return(structure(
      list(situacao = SITUACAO[["nao_verificado"]], dados = NULL,
           erro = conditionMessage(erro),
           notificar = !inherits(erro, "erro_sem_conexao")),
      class = "resultado_tema"
    ))
  }

  stopifnot(is.data.frame(dados))
  structure(
    list(situacao = if (nrow(dados) > 0) SITUACAO[["com"]] else SITUACAO[["sem"]],
         dados = dados, erro = NULL, notificar = FALSE),
    class = "resultado_tema"
  )
}

#' Verifica um tema sem deixar o erro escapar
#'
#' @param consulta Função sem argumentos que devolve a tabela de resultado.
#'
#' @return `resultado_tema`. Qualquer erro da consulta vira "não verificado".
#' @noRd
verificar_tema <- function(consulta) {
  tryCatch(
    resultado_tema(dados = consulta()),
    error = function(e) resultado_tema(erro = e)
  )
}

#' Erro de falta de conexão ao banco
#' @noRd
parar_sem_conexao <- function() {
  stop(structure(
    class = c("erro_sem_conexao", "error", "condition"),
    list(message = "banco de dados indisponível.", call = NULL)
  ))
}

#' Interferências de um tema vetorial do BD
#'
#' @description Consulta no SQL Server as feições do tema dentro do retângulo
#' envolvente da área de estudo e filtra, no R, as que intersectam a área.
#'
#' O filtro de interseção usa o GEOS (s2 desligado só aqui): o s2 rejeita alguns
#' polígonos que são válidos pelas regras OGC (ver "Geometrias inválidas para o
#' s2" em `dev/DECISOES.md`). Para um predicado de interseção, o resultado é na
#' prática o mesmo do cálculo esférico.
#'
#' @param con Conexão DBI ao SQL Server. NULL se a conexão falhou.
#' @param tabela String. Tabela ou view do tema.
#' @param area sf com a área de estudo, em EPSG:4674.
#' @param filtro_row Expressão para `dplyr::filter()` (ex.: retirar feições
#'   inativas), ou NULL.
#'
#' @return sf com as interferências e todos os atributos do tema.
#' @noRd
consultar_tema_bd <- function(con, tabela, area, filtro_row = NULL) {

  if (is.null(con)) parar_sem_conexao()

  filtro_bbox <- sf::st_as_text(sf::st_as_sfc(sf::st_bbox(area)))

  base_tema <- DBI::dbGetQuery(con, glue::glue(
    "SELECT *, ",
    "Shape.STAsText() AS wkt ",
    "FROM {tabela} ",
    "WHERE Shape.STIntersects(",
    "geometry::STGeomFromText('{filtro_bbox}', 4674)",
    ") = 1;"
  )) |>
    dplyr::mutate(Shape = sf::st_as_sfc(wkt, crs = 4674)) |>
    dplyr::select(-dplyr::any_of(c("wkt", "GDB_GEOMATTR_DATA"))) |>
    sf::st_as_sf()

  if (!is.null(filtro_row)) {
    base_tema <- dplyr::filter(base_tema, !!filtro_row)
  }

  s2_antes <- suppressMessages(sf::sf_use_s2(FALSE))
  on.exit(suppressMessages(sf::sf_use_s2(s2_antes)), add = TRUE)
  # sem o aviso "st_intersects assumes that they are planar": é intencional
  suppressMessages(sf::st_filter(base_tema, area, .predicate = sf::st_intersects))
}

#' Interferências de um tema vetorial lido de arquivo
#'
#' @description Provisório: só a Hidrografia ainda é lida de geodatabase, até
#' ganhar view no BD. Lê só o retângulo envolvente da área de estudo e corrige
#' a geometria antes da interseção (há bases com polígonos inválidos).
#'
#' @param caminho Caminho do arquivo (ex.: `.gdb`).
#' @param layer Camada a ler.
#' @param area sf com a área de estudo, em EPSG:4674.
#' @param filtro_row Expressão para `dplyr::filter()`, ou NULL.
#'
#' @return sf com as interferências.
#' @noRd
ler_tema_arquivo <- function(caminho, layer, area, filtro_row = NULL) {

  if (is.null(caminho) || caminho == "") {
    stop("caminho do arquivo não configurado.")
  }

  base_tema <- sf::st_read(
    caminho, layer = layer, quiet = TRUE,
    wkt_filter = sf::st_as_text(sf::st_as_sfc(sf::st_bbox(area)))
  ) |>
    sf::st_make_valid()

  if (!is.null(filtro_row)) {
    base_tema <- dplyr::filter(base_tema, !!filtro_row)
  }

  sf::st_filter(base_tema, area, .predicate = sf::st_intersects)
}
