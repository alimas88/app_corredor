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
#' @description Consulta no SQL Server só as feições do tema que intersectam o
#' polígono da área de estudo (e não o retângulo envolvente, que numa LT longa e
#' diagonal traz muito mais feições). A geometria vem em WKB, mais leve que o
#' WKT e sem perda de precisão, e a coluna `Shape` original não é trazida.
#'
#' Depois da consulta, o filtro de interseção é refeito no R com o GEOS (s2
#' desligado só aqui), como garantia: o s2 rejeita alguns polígonos que são
#' válidos pelas regras OGC (ver "Geometrias inválidas para o s2" em
#' `dev/DECISOES.md`). O SQL Server e o GEOS calculam no plano, então os dois
#' filtros dão o mesmo resultado.
#'
#' @param con Conexão DBI ao SQL Server. NULL se a conexão falhou.
#' @param tabela String. Tabela ou view do tema (aceita `esquema.tabela`).
#' @param area sf ou sfc com a área de estudo, em EPSG:4674.
#' @param filtro_row Expressão para `dplyr::filter()` (ex.: retirar feições
#'   inativas), ou NULL.
#'
#' @return sf com as interferências e todos os atributos do tema.
#' @noRd
consultar_tema_bd <- function(con, tabela, area, filtro_row = NULL) {

  if (is.null(con)) parar_sem_conexao()

  area <- sf::st_union(sf::st_geometry(area))
  colunas <- colunas_tema_bd(con, tabela)

  # A coluna da geometria em WKB (varbinary(max)) vai por último (driver ODBC)
  base_tema <- DBI::dbGetQuery(con, glue::glue(
    "SELECT {colunas}, Shape.STAsBinary() AS wkb ",
    "FROM {tabela} ",
    "WHERE Shape.STIntersects({sql_geometria(area)}) = 1;"
  )) |>
    dplyr::mutate(Shape = ler_wkb(wkb), .keep = "unused") |>
    sf::st_as_sf()

  if (!is.null(filtro_row)) {
    base_tema <- dplyr::filter(base_tema, !!filtro_row)
  }

  s2_antes <- suppressMessages(sf::sf_use_s2(FALSE))
  on.exit(suppressMessages(sf::sf_use_s2(s2_antes)), add = TRUE)
  # sem o aviso "st_intersects assumes that they are planar": é intencional
  suppressMessages(sf::st_filter(base_tema, area, .predicate = sf::st_intersects))
}

#' Colunas de atributos de um tema do BD, prontas para o SELECT
#'
#' @description Lista as colunas da tabela ou view, sem a geometria (`Shape`,
#' trazida à parte em WKB), as colunas de tipo espacial e a
#' `GDB_GEOMATTR_DATA` (dado interno do ArcGIS). As colunas de tamanho máximo
#' (`varchar(max)`, `nvarchar(max)`, `varbinary(max)`) vão para o fim: o driver
#' ODBC do SQL Server exige que elas venham depois das demais.
#'
#' @param con Conexão DBI ao SQL Server.
#' @param tabela String. Tabela ou view (aceita `esquema.tabela`).
#'
#' @return String com os nomes entre colchetes, separados por vírgula.
#' @noRd
colunas_tema_bd <- function(con, tabela) {

  colunas <- DBI::dbGetQuery(con, glue::glue(
    "SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH ",
    "FROM INFORMATION_SCHEMA.COLUMNS ",
    "WHERE TABLE_NAME = PARSENAME('{tabela}', 1) ",
    "AND (PARSENAME('{tabela}', 2) IS NULL OR TABLE_SCHEMA = PARSENAME('{tabela}', 2)) ",
    "ORDER BY ORDINAL_POSITION;"
  ))

  if (nrow(colunas) == 0) {
    stop("tabela ", tabela, " não encontrada no banco.")
  }

  colunas <- colunas |>
    dplyr::filter(
      !tolower(COLUMN_NAME) %in% c("shape", "gdb_geomattr_data"),
      !tolower(DATA_TYPE) %in% c("geometry", "geography")
    ) |>
    dplyr::arrange(dplyr::coalesce(CHARACTER_MAXIMUM_LENGTH == -1, FALSE))

  if (nrow(colunas) == 0) return("NULL AS sem_atributos")

  paste0("[", stringr::str_replace_all(colunas$COLUMN_NAME, stringr::fixed("]"), "]]"), "]",
         collapse = ", ")
}

#' Geometria da área de estudo em SQL
#'
#' @description Expressão `geometry` do SQL Server com o polígono da área de
#' estudo, com todas as casas decimais (o padrão do `st_as_text()` arredonda
#' para 7 algarismos significativos, ~1 m) e `MakeValid()`.
#'
#' @param area sfc com a área de estudo, já no SRID `srid`.
#' @param srid SRID da geometria no banco.
#'
#' @return String.
#' @noRd
sql_geometria <- function(area, srid = 4674) {
  wkt <- sf::st_as_text(sf::st_union(sf::st_geometry(area)), digits = 15)
  glue::glue("geometry::STGeomFromText('{wkt}', {srid}).MakeValid()")
}

#' Converte a geometria WKB lida do banco em sfc
#'
#' @param wkb Lista de vetores raw (ou `blob`), como o ODBC devolve
#'   `varbinary(max)`.
#' @param crs CRS da geometria.
#'
#' @return sfc.
#' @noRd
ler_wkb <- function(wkb, crs = 4674) {
  sf::st_as_sfc(structure(lapply(wkb, as.raw), class = "WKB"), crs = crs)
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
