# Compara o filtro espacial antigo (retângulo envolvente + WKT) com o novo
# (polígono da área de estudo + WKB) num corredor real.
#
# Só leitura: não grava nada no banco.
# Uso: abrir o projeto, ajustar `zip_area` e `temas` e rodar o script inteiro.
# Rode duas vezes e use a segunda: na primeira, o cache do servidor favorece
# a consulta que roda depois.

devtools::load_all()

zip_area <- "caminho/para/area_de_estudo.zip"           # shapefile da área de estudo
temas    <- c("processos_minerarios", "rodovias")       # chaves do golem-config.yml

area <- ler_corredor(zip_area)
con  <- conectar_bd()

# filtro antigo: o mesmo do commit eba565c (mod_banco)
consultar_bbox <- function(con, tabela, area) {
  filtro_bbox <- sf::st_as_text(sf::st_as_sfc(sf::st_bbox(area)))
  base <- DBI::dbGetQuery(con, glue::glue(
    "SELECT *, Shape.STAsText() AS wkt FROM {tabela} ",
    "WHERE Shape.STIntersects(geometry::STGeomFromText('{filtro_bbox}', 4674)) = 1;"
  ))
  n_banco <- nrow(base)
  base <- base |>
    dplyr::mutate(Shape = sf::st_as_sfc(wkt, crs = 4674)) |>
    dplyr::select(-dplyr::any_of(c("wkt", "GDB_GEOMATTR_DATA"))) |>
    sf::st_as_sf()
  s2_antes <- suppressMessages(sf::sf_use_s2(FALSE))
  on.exit(suppressMessages(sf::sf_use_s2(s2_antes)), add = TRUE)
  list(n_banco = n_banco,
       dados = suppressMessages(sf::st_filter(base, area, .predicate = sf::st_intersects)))
}

medir <- function(chave) {
  tabela <- tabela_tema(chave)

  t_antigo <- system.time(antigo <- consultar_bbox(con, tabela, area))[["elapsed"]]
  t_novo   <- system.time(novo <- consultar_tema_bd(con, tabela, area))[["elapsed"]]

  dplyr::tibble(
    tema = chave,
    feicoes_do_banco_antigo = antigo$n_banco,
    interferencias_antigo = nrow(antigo$dados),
    interferencias_novo = nrow(novo),
    segundos_antigo = t_antigo,
    segundos_novo = t_novo
  )
}

resultado <- purrr::map(temas, medir) |> purrr::list_rbind()
print(resultado)

# As interferências devem ser as mesmas nos dois filtros.
stopifnot(resultado$interferencias_antigo == resultado$interferencias_novo)

DBI::dbDisconnect(con)
