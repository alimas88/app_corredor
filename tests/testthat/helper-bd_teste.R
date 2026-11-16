# Banco de teste local para os testes de integração (ver dev/bd_teste.sh).
# Sem as variáveis ANALISE_BD_TESTE_*, os testes de integração são pulados.

#' Conexão ao banco de teste
#'
#' Só aceita servidor local: se as variáveis apontarem para outro servidor
#' (ex.: o de produção), o teste falha em vez de rodar.
conectar_bd_teste <- function(env = parent.frame()) {

  servidor <- Sys.getenv("ANALISE_BD_TESTE_SERVER")
  if (servidor == "") {
    testthat::skip("sem banco de teste (rode dev/bd_teste.sh)")
  }
  if (!grepl("^(127\\.0\\.0\\.1|localhost)([,:]|$)", servidor)) {
    stop("O banco de teste deve ser local (127.0.0.1 ou localhost), e não ", servidor, ".")
  }

  con <- tryCatch(
    DBI::dbConnect(odbc::odbc(),
                   Driver = Sys.getenv("ANALISE_BD_TESTE_DRIVER"),
                   Server = servidor,
                   Database = Sys.getenv("ANALISE_BD_TESTE_DATABASE"),
                   UID = Sys.getenv("ANALISE_BD_TESTE_UID"),
                   PWD = Sys.getenv("ANALISE_BD_TESTE_SENHA"),
                   Encrypt = "yes", TrustServerCertificate = "yes"),
    error = function(e) testthat::skip(paste("banco de teste indisponível:", conditionMessage(e)))
  )
  withr::defer(DBI::dbDisconnect(con), envir = env)
  con
}

#' Cria uma tabela TESTE_ e a apaga ao fim do teste
#'
#' @param sql_criar Comandos SQL que criam e preenchem a tabela (ou view).
criar_tabela_teste <- function(con, nome, sql_criar, tipo = "TABLE", env = parent.frame()) {
  stopifnot(startsWith(nome, "TESTE_"))
  apagar <- glue::glue("IF OBJECT_ID('{nome}') IS NOT NULL DROP {tipo} {nome};")
  DBI::dbExecute(con, apagar)
  purrr::walk(sql_criar, \(sql) DBI::dbExecute(con, sql))
  withr::defer(DBI::dbExecute(con, apagar), envir = env)
  invisible(nome)
}
