#' Conexão ao banco de dados
#'
#' @description Abre a conexão ODBC com os parâmetros da seção `bd` do
#' `golem-config.yml`, que por sua vez lê as variáveis de ambiente
#' `ANALISE_BD_DRIVER`, `ANALISE_BD_SERVER` e `ANALISE_BD_DATABASE`.
#'
#' @param cfg Lista com `driver`, `server` e `database`.
#'
#' @return Conexão DBI.
#' @noRd
conectar_bd <- function(cfg = get_golem_config("bd")) {

  faltam <- names(purrr::keep(cfg[c("server", "database")], \(x) is.null(x) || x == ""))
  if (length(faltam) > 0) {
    stop("Configuração do banco incompleta (", paste(faltam, collapse = ", "),
         "). Defina as variáveis ANALISE_BD_* no .Renviron.")
  }

  DBI::dbConnect(odbc::odbc(),
                 Driver = cfg$driver,
                 Server = cfg$server,
                 Database = cfg$database,
                 Trusted_Connection = "Yes")
}

#' Nome da tabela de um tema no BD
#'
#' @param chave String. Chave do tema na seção `temas` do `golem-config.yml`.
#'
#' @return character
#' @noRd
tabela_tema <- function(chave) {

  nome <- get_golem_config("temas")[[chave]]
  if (is.null(nome) || nome == "") {
    stop("Tema '", chave, "' sem tabela definida no golem-config.yml.")
  }
  nome
}

#' Filtro de linhas definido no golem-config.yml
#'
#' @param chave String. Chave do filtro no `golem-config.yml`.
#'
#' @return Expressão R (para `dplyr::filter(!!filtro)`) ou NULL.
#' @noRd
filtro_config <- function(chave) {

  texto <- get_golem_config(chave)
  if (is.null(texto) || texto == "") return(NULL)
  rlang::parse_expr(texto)
}
