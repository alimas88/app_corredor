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
