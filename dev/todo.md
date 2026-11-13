# TODO - Para fazer

## Para fazer



---
## Melhorias

- aceitar KML, gpkg e outros

- Carregar as interferências no mapa
  - estabelecer simbologia para cada dado
  - criar os checkbox no mapa para des/habilitação das camadas

- substituir input do corredor por input do eixo e possbilidade de o usuário fazer o buffer

- implementar maneira de resumir alguns dos dados. Ex.: processo minerário (ao invés
de apresentar todos os PM, resumir por subtância e fase). O mesmo para rodovias, LTs.
Pensar em como fazer isso mantendo a genericidade das funções (ou criar várias funções
para cada demanda - inicialmente acho pior)

- Construir algum indicador de densidade de acessos/vias.

---

## Notas técnicas

### 1. `filtro_row`

Se a consulta falhar, o `tryCatch` devolve `NULL` e a linha `base_tema %>% dplyr::filter(!!filtro_row)` quebraria com erro, em vez de tratar a falha com elegância (hoje protegido por `!is.null(base_tema)`).

### 2. O que `return(NULL)` faz dentro do `moduleServer`

O `moduleServer(id, function(input, output, session) {...})` apenas **executa essa função uma vez**, e o corpo dela é que registra os `reactive()` e os `output$...`. Um `return()` no meio encerra a função ali, então tudo o que vem depois **nunca é registrado**:

```r
moduleServer(id, function(input, output, session){
  if (is.null(con)) {
    showNotification(...)
    return(NULL)        # <- sai aqui
  }
  ...
  output$tabela_sobreposicao <- DT::renderDT(...)   # nunca é executado
})
```

Sem `con`, o módulo existe, mas não tem nenhum output. O `DTOutput` na UI fica vazio, sem mensagem e sem erro. Só a notificação, que some em 10 s, avisa que algo deu errado.

O `return(NULL)` dentro do handler do `tryCatch(error = function(e) ...)` é diferente: ali ele só encerra a função do handler e define o valor de `base_tema`.

A alternativa é deixar o módulo registrar os outputs sempre e mostrar a mensagem no lugar da tabela:

```r
output$tabela_sobreposicao <- DT::renderDT({
  validate(need(!is.null(con), "Banco de dados indisponível."))
  validate(need(!is.null(base_tema), "Falha ao carregar este tema."))
  ...
})
```

### 3. Módulos dentro do `observeEvent`

O bloco do `observeEvent(shp_corredor(), {...})` roda de novo a cada novo upload. Cada execução chama `mod_banco_server('infra_municipio', ...)` outra vez com o mesmo `id`. O Shiny não avisa e não cancela a instância anterior:

- Os `output$tabela_sobreposicao` são reatribuídos, então vale o último.
- Os `reactive()` da instância antiga deixam de ser usados e ficam como lixo na sessão.
- **Toda a consulta ao banco roda de novo, para todos os ~20 temas, a cada upload**, porque a consulta está no corpo do módulo e não dentro de um `reactive`.

Se algum módulo tiver `observe()` ou `observeEvent()` (um botão de download, um clique no mapa), cada re-registro cria mais um observer vivo com o mesmo gatilho, e o evento passa a disparar N vezes.

**O padrão mais seguro** é registrar os módulos uma vez, fora do `observeEvent`, e fazer a consulta ao banco dentro de um `reactive` que depende do corredor:

```r
base_tema <- reactive({
  req(shp_corredor())
  # consulta ao banco aqui
})
```

### 4. Enviar o corredor ao banco em vez do bbox

Hoje o bbox só serve de pré-filtro, e o cruzamento exato acontece no R com `st_filter`. O polígono pode ir no lugar do bbox:

```r
wkt_corredor <- sf::st_as_text(sf::st_geometry(corredor), digits = 6)
```

Com isso, o SQL Server devolve só as feições que realmente intersectam. Para um corredor diagonal e comprido, o bbox cobre muita área vazia, então o ganho é grande.

**Cuidados:**

- **Tamanho do WKT.** Um buffer de 10 km ao redor de uma linha pode ter milhares de vértices. `digits = 6` já reduz o texto; `sf::st_simplify()` ajuda se ainda ficar pesado.
- **Desempenho com o índice espacial.** Se o `STIntersects` com polígono complexo ficar lento, usar os dois: `Shape.Filter(bbox) = 1 AND Shape.STIntersects(poligono) = 1`.
- **Geometria válida e SRID.** O corredor deve passar por `st_make_valid()` e estar em 4674.
- **Passar como parâmetro, não por concatenação.** `DBI::dbGetQuery(con, sql, params = list(wkt))` com `?` no SQL.
- **Geodatabases (`st_read(wkt_filter=)`).** O filtro espacial do GDAL usa em geral só o envelope da geometria; o `st_filter` no R continua necessário.

Se o polígono for grande demais para ir como texto, a alternativa é gravá-lo numa tabela temporária (`#corredor`) e fazer um `JOIN` espacial no servidor.
