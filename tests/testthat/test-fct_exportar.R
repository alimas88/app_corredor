# Planilha de conferência: preparação e escrita do xlsx

test_that("nomes_abas_validos() respeita as regras do Excel", {
  nomes <- c("Processos/Minerários", "a:b*c?", "[UC]", "", "Unidades de Conservação Federais e Estaduais")

  validos <- nomes_abas_validos(nomes)

  expect_false(any(stringr::str_detect(validos, "[\\[\\]:*?/\\\\]")))
  expect_true(all(nchar(validos) <= 31))
  expect_equal(validos[1:4], c("Processos Minerários", "a b c", "UC", "Aba"))
})

test_that("nomes_abas_validos() desfaz repetições, inclusive após truncar", {
  nomes <- c("Rodovias", "Rodovias",
             "Nome muito longo de um tema qualquer A", "Nome muito longo de um tema qualquer B")

  validos <- nomes_abas_validos(nomes)

  expect_equal(anyDuplicated(validos), 0L)
  expect_true(all(nchar(validos) <= 31))
})

test_that("preparar_aba() tira a geometria e converte list-columns em texto", {
  dados <- area_estudo_teste()
  dados$lista <- list(c("a", "b"))

  aba <- preparar_aba(dados)

  expect_false(inherits(aba, "sf"))
  expect_false("geometry" %in% names(aba))
  expect_equal(aba$lista, "a; b")
})

test_that("escrever_xlsx() grava o Resumo com a situação e uma aba por tema verificado", {
  skip_if_not_installed("readxl")

  resultados <- list(
    "Terras Indígenas" = resultado_tema(dplyr::tibble(nome = c("A", "B"))),
    "Rodovias" = resultado_tema(dplyr::tibble(nome = character(0))),
    "Processos/Minerários" = resultado_tema(erro = simpleError("tempo esgotado"))
  )
  arquivo <- withr::local_tempfile(fileext = ".xlsx")

  escrever_xlsx(resultados, arquivo)

  # tema não verificado não tem aba
  expect_equal(readxl::excel_sheets(arquivo), c("Resumo", "Terras Indígenas", "Rodovias"))

  resumo <- readxl::read_excel(arquivo, sheet = "Resumo")
  expect_equal(resumo$Tema, c("Processos/Minerários", "Terras Indígenas", "Rodovias"))
  expect_equal(resumo$`Situação`,
               c("não verificado", "com interferência", "sem interferência"))
  expect_equal(resumo$Registros, c(NA, 2, 0))
  expect_equal(resumo$Aba, c(NA, "Terras Indígenas", "Rodovias"))
  expect_equal(resumo$`Observação`, c("tempo esgotado", NA, NA))
})

test_that("escrever_xlsx() não repete o nome da aba Resumo", {
  skip_if_not_installed("readxl")

  resultados <- list(Resumo = resultado_tema(dplyr::tibble(x = 1)))
  arquivo <- withr::local_tempfile(fileext = ".xlsx")

  escrever_xlsx(resultados, arquivo)

  expect_equal(readxl::excel_sheets(arquivo), c("Resumo", "Resumo_1"))
})
