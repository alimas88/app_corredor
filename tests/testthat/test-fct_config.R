# Leitura do golem-config.yml

test_that("tabela_tema() devolve a tabela configurada e falha sem ela", {
  expect_type(tabela_tema("terras_indigenas"), "character")
  expect_error(tabela_tema("tema_inexistente"), "sem tabela definida")
})

test_that("filtro_config() devolve NULL quando o filtro está vazio", {
  expect_null(filtro_config("filtro_linhas_transmissao"))
})

test_that("conectar_bd() avisa quando faltam variáveis de ambiente", {
  cfg <- list(driver = "ODBC Driver 18 for SQL Server", server = "", database = "")
  expect_error(conectar_bd(cfg), "server, database")
})
