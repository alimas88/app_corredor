#' Tipos de tema e os campos obrigatórios de cada um
#' @noRd
CAMPOS_TIPO <- list(
  vetor_bd = "tabela",
  raster_bd = c("tabela", "legenda"),
  vetor_arquivo = c("caminho", "camada")
)

#' Catálogo de temas
#'
#' @description Lê e confere a seção `temas` do `golem-config.yml`. Um catálogo
#' com problema impede o app de iniciar, com a mensagem do problema.
#'
#' @param temas Lista da seção `temas` (padrão: a do `golem-config.yml`).
#'
#' @return Lista nomeada pela chave do tema, na ordem do catálogo. Cada tema é
#'   uma lista com `chave` e os campos do YAML; `subgrupo` vem preenchido com o
#'   grupo quando ausente.
#' @noRd
catalogo_temas <- function(temas = get_golem_config("temas")) {

  if (length(temas) == 0 || is.null(names(temas))) {
    stop("Catálogo de temas vazio ou sem chaves no golem-config.yml (seção temas).")
  }

  catalogo <- purrr::imap(temas, function(tema, chave) {

    if (!is.list(tema)) {
      stop("Tema '", chave, "' do catálogo não tem campos (nome, grupo, tipo ...).")
    }
    tema$chave <- chave

    faltam <- setdiff(c("nome", "grupo", "tipo"), names(purrr::compact(tema)))
    if (length(faltam) > 0) {
      stop("Tema '", chave, "' do catálogo sem: ", paste(faltam, collapse = ", "), ".")
    }
    if (!tema$tipo %in% names(CAMPOS_TIPO)) {
      stop("Tema '", chave, "' com tipo desconhecido (", tema$tipo, "). Tipos: ",
           paste(names(CAMPOS_TIPO), collapse = ", "), ".")
    }
    # campos vazios no YAML (~ ou "") contam como ausentes
    preenchidos <- names(purrr::discard(tema, \(x) is.null(x) || identical(x, "")))
    faltam <- setdiff(CAMPOS_TIPO[[tema$tipo]], preenchidos)
    if (length(faltam) > 0 && tema$tipo != "vetor_arquivo") {
      stop("Tema '", chave, "' (", tema$tipo, ") sem: ", paste(faltam, collapse = ", "), ".")
    }
    # vetor_arquivo sem caminho não impede o app: o tema fica "não verificado"

    tema$subgrupo <- tema$subgrupo %||% tema$grupo
    tema
  })

  nomes <- purrr::map_chr(catalogo, "nome")
  if (anyDuplicated(nomes)) {
    stop("Nomes de tema repetidos no catálogo: ",
         paste(unique(nomes[duplicated(nomes)]), collapse = ", "), ".")
  }

  catalogo
}

#' Nome da tabela de um tema no BD
#'
#' @param chave String. Chave do tema no catálogo.
#' @param catalogo Saída de `catalogo_temas()`.
#'
#' @return character
#' @noRd
tabela_tema <- function(chave, catalogo = catalogo_temas()) {

  nome <- catalogo[[chave]]$tabela
  if (is.null(nome) || nome == "") {
    stop("Tema '", chave, "' sem tabela definida no golem-config.yml.")
  }
  nome
}

#' Função de consulta de um tema do catálogo
#'
#' @description Monta, a partir do tipo do tema, a função que recebe a área de
#' estudo e devolve a tabela de resultado. É o que o `mod_tema_server()` usa.
#'
#' @param tema Um elemento de `catalogo_temas()`.
#' @param con Conexão DBI ao SQL Server, ou NULL se a conexão falhou.
#'
#' @return Função de um argumento (a área de estudo).
#' @noRd
consulta_tema <- function(tema, con) {

  filtro <- if (is.null(tema$filtro) || tema$filtro == "") NULL else rlang::parse_expr(tema$filtro)

  switch(
    tema$tipo,
    vetor_bd = \(area) consultar_tema_bd(con, tema$tabela, area, filtro),
    vetor_arquivo = \(area) ler_tema_arquivo(tema$caminho, tema$camada, area, filtro),
    raster_bd = {
      legenda <- legenda_raster(tema)
      validar_legenda(legenda, tema$nome)
      \(area) resumir_raster_bd(con, tema$tabela, area, legenda,
                                ordem = tema$ordem %||% "percentagem",
                                todas_classes = isTRUE(tema$todas_classes))
    }
  )
}

#' Legenda de um tema raster, pronta para `resumir_raster_bd()`
#'
#' @description
#' - "mapbiomas": `legenda_mapbiomas` filtrada pela `colecao` do tema (a mesma
#'   do raster da tabela).
#' - "declividade": `legenda_declividade` com a coluna `faixa` (ex.: "0 a 3%",
#'   "> 75%").
#'
#' @param tema Um elemento de `catalogo_temas()`.
#'
#' @return data.frame com `class_id`, `descricao`, colunas extras e `color`.
#' @noRd
legenda_raster <- function(tema) {
  switch(
    tema$legenda,
    mapbiomas = {
      if (is.null(tema$colecao)) {
        stop("Tema '", tema$chave, "' sem a coleção do MapBiomas (campo colecao).")
      }
      legenda_mapbiomas |>
        dplyr::filter(colecao == tema$colecao) |>
        dplyr::select(class_id, descricao, color)
    },
    declividade = legenda_declividade |>
      dplyr::mutate(faixa = dplyr::if_else(
        is.na(lim_sup),
        paste0("> ", lim_inf, "%"),
        paste0(lim_inf, " a ", lim_sup, "%")
      )) |>
      dplyr::select(class_id, descricao, faixa, color),
    stop("Legenda desconhecida no tema '", tema$chave, "': ", tema$legenda,
         ". Legendas: mapbiomas, declividade.")
  )
}

#' Colunas técnicas, fora da interface quando o tema não tem lista de colunas
#' @noRd
COLUNAS_TECNICAS <- c("objectid", "objectid_1", "fid", "shape", "shape_length",
                      "shape_area", "shape_leng", "globalid", "gdb_geomattr_data")

#' Colunas exibidas de uma tabela de resultado
#'
#' @description Para a interface e a síntese. Com a lista `colunas` do
#' catálogo, mostra só essas, nessa ordem (as que não existirem na tabela são
#' ignoradas). Sem lista, mostra todas menos as técnicas. A planilha de
#' conferência não passa por aqui: traz todas.
#'
#' @param dados data.frame (sem geometria).
#' @param colunas Vetor de nomes, ou NULL.
#'
#' @return data.frame.
#' @noRd
colunas_exibidas <- function(dados, colunas = NULL) {
  if (length(colunas) > 0) {
    return(dplyr::select(dados, dplyr::any_of(unlist(colunas))))
  }
  dplyr::select(dados, !dplyr::any_of(names(dados)[tolower(names(dados)) %in% COLUNAS_TECNICAS]))
}
