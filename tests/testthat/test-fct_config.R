# Leitura do golem-config.yml

test_that("conectar_bd() avisa quando faltam variáveis de ambiente", {
  cfg <- list(driver = "ODBC Driver 18 for SQL Server", server = "", database = "")
  expect_error(conectar_bd(cfg), "server, database")
})
