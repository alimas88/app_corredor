# Catálogo de temas (golem-config.yml, seção temas)

test_that("o catálogo do golem-config.yml é válido e mantém a ordem", {
  catalogo <- catalogo_temas()

  expect_gt(length(catalogo), 20)
  expect_equal(names(catalogo)[1:2], c("municipios", "areas_urbanas"))
  expect_equal(anyDuplicated(purrr::map_chr(catalogo, "nome")), 0L)
  expect_true(all(purrr::map_chr(catalogo, "tipo") %in% names(CAMPOS_TIPO)))
  # sem subgrupo, a caixa é o próprio grupo
  expect_equal(catalogo$cavernas$subgrupo, "Meio Físico")
  expect_equal(catalogo$municipios$subgrupo, "Político/Administrativo")
})

test_that("todo tema do catálogo vira uma função de consulta", {
  catalogo <- catalogo_temas()

  consultas <- purrr::map(catalogo, \(t) consulta_tema(t, con = NULL))

  expect_true(all(purrr::map_lgl(consultas, is.function)))
  # sem conexão, os temas do BD ficam "não verificados"
  r <- verificar_tema(\() consultas$terras_indigenas(area_estudo_teste()))
  expect_equal(r$situacao, "não verificado")
})

test_that("as legendas dos rasters do catálogo são válidas", {
  catalogo <- catalogo_temas()

  mapbiomas <- legenda_raster(catalogo$mapbiomas)
  expect_gt(nrow(mapbiomas), 30)
  expect_named(mapbiomas, c("class_id", "descricao", "color"))

  declividade <- legenda_raster(catalogo$declividade)
  expect_equal(declividade$faixa[c(1, 6)], c("0 a 3%", "> 75%"))
  expect_invisible(validar_legenda(declividade, "Declividade"))
})

test_that("tabela_tema() devolve a tabela do catálogo e falha sem ela", {
  expect_type(tabela_tema("terras_indigenas"), "character")
  expect_error(tabela_tema("tema_inexistente"), "sem tabela definida")
})

tema_ok <- list(nome = "A", grupo = "G", tipo = "vetor_bd", tabela = "TEMA_A")

test_that("catalogo_temas() recusa catálogo com problema", {
  expect_error(catalogo_temas(list()), "vazio")
  expect_error(catalogo_temas(list(a = "TEMA_A")), "não tem campos")
  expect_error(catalogo_temas(list(a = tema_ok[-2])), "sem: grupo")
  expect_error(catalogo_temas(list(a = modifyList(tema_ok, list(tipo = "wms")))),
               "tipo desconhecido")
  expect_error(catalogo_temas(list(a = modifyList(tema_ok, list(tabela = "")))),
               "\\(vetor_bd\\) sem: tabela")
  expect_error(catalogo_temas(list(a = tema_ok, b = tema_ok)), "repetidos no catálogo: A")
  raster <- list(nome = "R", grupo = "G", tipo = "raster_bd", tabela = "T")
  expect_error(catalogo_temas(list(r = raster)), "sem: legenda")
})

test_that("legenda_raster() exige a coleção do MapBiomas e uma legenda conhecida", {
  expect_error(legenda_raster(list(chave = "m", legenda = "mapbiomas")), "coleção")
  expect_error(legenda_raster(list(chave = "x", legenda = "solos")), "Legenda desconhecida")
})

test_that("consulta_tema() aplica o filtro do catálogo", {
  local_mocked_bindings(consultar_tema_bd = function(con, tabela, area, filtro_row) {
    list(tabela = tabela, filtro = filtro_row)
  })
  tema <- modifyList(tema_ok, list(filtro = "situacao == 'Ativo'"))

  r <- consulta_tema(tema, con = "con")(area_estudo_teste())

  expect_equal(r$tabela, "TEMA_A")
  expect_equal(r$filtro, rlang::expr(situacao == "Ativo"))
  expect_null(consulta_tema(tema_ok, "con")(NULL)$filtro)
})

test_that("colunas_exibidas() usa a lista do catálogo ou tira as colunas técnicas", {
  dados <- data.frame(OBJECTID = 1, nome = "a", uf = "GO", Shape_Length = 2)

  expect_named(colunas_exibidas(dados), c("nome", "uf"))
  expect_named(colunas_exibidas(dados, list("uf", "nome", "inexistente")), c("uf", "nome"))
})

test_that("id_grupo() gera identificadores sem acento", {
  expect_equal(id_grupo("Meio Físico"), "meio_fisico")
  expect_equal(id_grupo("Processos Minerários"), "processos_minerarios")
})
