# Registro de resultados

test_that("registro_adicionar() mantém a ordem e substitui a aba existente", {
  registro <- registro_criar()

  registro_adicionar(registro, "A", shiny::reactive(1))
  registro_adicionar(registro, "B", shiny::reactive(2))
  registro_adicionar(registro, "A", shiny::reactive(3))

  lista <- shiny::isolate(registro())
  expect_named(lista, c("A", "B"))
  expect_equal(shiny::isolate(lista$A()), 3)
})

test_that("registro_adicionar() não faz nada sem registro e exige reactive", {
  expect_null(registro_adicionar(NULL, "A", shiny::reactive(1)))
  expect_error(registro_adicionar(registro_criar(), "A", 1))
})

test_that("coletar_resultados() avalia os reactives e descarta os que falham", {
  registro <- registro_criar()
  registro_adicionar(registro, "ok", shiny::reactive(area_estudo_teste()))
  registro_adicionar(registro, "falhou", shiny::reactive(stop("erro")))
  registro_adicionar(registro, "sem área", shiny::reactive(shiny::req(NULL)))

  resultados <- coletar_resultados(registro)

  expect_named(resultados, "ok")
  expect_false(inherits(resultados$ok, "sf"))
})
