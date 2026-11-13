# Módulo genérico do tema

test_that("mod_tema_server() verifica o tema quando a área de estudo chega", {
  area <- shiny::reactiveVal(NULL)
  registro <- registro_criar()
  chamadas <- 0

  shiny::testServer(mod_tema_server, args = list(
    area = area, tema = "Teste", registro = registro,
    consulta = \(a) { chamadas <<- chamadas + 1; dplyr::tibble(id = a$id) }
  ), {
    expect_named(registro(), "Teste")
    expect_length(coletar_resultados(registro), 0)   # sem área de estudo

    area(area_estudo_teste())
    session$flushReact()

    expect_equal(chamadas, 1)   # roda sem a tabela estar visível
    expect_equal(resultado()$situacao, "com interferência")
    expect_equal(coletar_resultados(registro)$Teste$situacao, "com interferência")
  })
})

test_that("mod_tema_server() marca 'não verificado' quando a consulta falha", {
  area <- shiny::reactiveVal(area_estudo_teste())

  shiny::testServer(mod_tema_server, args = list(
    area = area, tema = "Teste", consulta = \(a) stop("tabela inexistente")
  ), {
    session$flushReact()
    expect_equal(resultado()$situacao, "não verificado")
    expect_error(output$tabela, "Tema não verificado: tabela inexistente")
  })
})
