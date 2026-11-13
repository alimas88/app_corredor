# analise.corredor: decisões e pendências

Registro das decisões da sessão de definição de 21/10/2026, atualizado em 10, 11, 12 e 13/11/2026 com as decisões sobre rasters, legendas do MapBiomas, declividade, geometrias inválidas para o s2 e validação do envio da área de estudo. O vocabulário está em `dev/CONTEXT.md`.

## Decidido

- **Objetivo:** otimizar e viabilizar a publicação do app. Os temas entram aos poucos.
- **Área de estudo:** uma por análise. Gerada por buffer do traçado (ponto, linha ou ambos) ou enviada pronta. Polígono enviado é usado como veio, e a distância de buffer fica desabilitada.
- **Distância de buffer:** única para todos os temas. Testa-se um valor por vez: alterar a distância recalcula e descarta os resultados anteriores.
- **SE + LT em conjunto:** permitido. O usuário envia os dois traçados ou uma área de estudo pronta, e o app une tudo em um só polígono.
- **Interferência:** só o que intersecta diretamente a área de estudo. A faixa de proximidade (ex.: aeródromos a 3 km) não será implantada agora.
- **Situação do tema:** três estados (com interferência, sem interferência, não verificado). Temas não verificados aparecem em destaque na síntese e na planilha, e a geração do Word avisa antes de exportar.
- **Saídas:** planilha de conferência (xlsx, uma aba por tema) e síntese das interferências (Word de apoio, uma tabela por tema com o nome do tema). Por ora, sem resumos nem regras por tema.
- **Configuração:** conexão ao banco e nomes das tabelas de cada tema ficam no `inst/golem-config.yml`, que lê os dados sensíveis de variáveis de ambiente (`.Renviron`, ver `.Renviron.exemplo`). Nenhum servidor, banco, usuário ou nome de tabela fica no código.
- **Rasters (MapBiomas, declividade):** gravados no SQL Server em tiles GeoTIFF e lidos pelo app direto do banco (decisão de 10/11/2026, substitui a de 21/10/2026, que previa COG em pasta acessível ao servidor). Motivo: o servidor Shiny não acessa unidades de rede. Detalhes na seção "Rasters no SQL Server".
- **Declividade:** % da área de estudo por classe, no mesmo formato do MapBiomas. Fonte: Topodata SC (INPE, ~30 m, 6 classes Embrapa) (decisão de 11/11/2026). Detalhes na seção "Declividade: Topodata SC".
- **Dados vetoriais:** a meta é ler tudo do SQL Server. Os temas ainda lidos de arquivo ganham views no banco.
- **Colunas exibidas:** lista de colunas por tema no catálogo, usada na síntese e na interface. É configuração, não regra de resumo. Sem lista, entram todas as colunas menos as técnicas. A planilha de conferência traz todas.
- **Sistema de referência:** buffer e áreas calculados de forma geodésica em SIRGAS 2000 geográfico (4674), com `sf` + `s2`. Não depende de fuso. Os valores podem diferir um pouco dos do ArcGIS/QGIS. Exceção: o filtro de interseção dos temas vetoriais do BD usa GEOS (decisão de 12/11/2026, ver "Geometrias inválidas para o s2").
- **Distância de buffer na interface:** em km, com decimais (ex.: 0,04 km = 40 m, faixa de servidão). Campo vazio por padrão, aceita qualquer valor positivo e não tem limite máximo. O app também serve a outros usos, como a faixa de servidão.
- **Framework de UI:** a reestruturação é feita em `bslib` (decisão de 21/10/2026, substitui a preferência anterior por `bs4Dash`).
- **Entrada:** `.zip` (shapefile), `.kml/.kmz`, `.gpkg` e `.zip` com `.gdb`. Com várias camadas, o usuário escolhe uma. O tipo de geometria detectado define se a distância é obrigatória (ponto e linha) ou fica desabilitada (polígono).
- **Mapa:** módulo próprio (`mod_mapa`), separado do módulo do traçado. Mostra o traçado, a área de estudo e as interferências por tema em camadas que se ligam e desligam, com popups e legenda. O mapa estático na síntese fica para depois.
- **Telas:** navegação por barra superior (`page_navbar`), com barra lateral só na página Análise. Validado no protótipo v2 (`dev/prototipos/prototipo_sintese.html`).
  - **Análise:** barra lateral com envio do arquivo, escolha de camada, geometria detectada, distância e botões; mapa ao lado.
  - **Síntese:** mestre-detalhe (variante A). Lista de temas à esquerda, com filtro por situação; à direita, o resumo do tema acima da tabela de resultado.
  - Exportar planilha e síntese só fica habilitado depois da análise.

### Fluxo do buffer: dois botões, nada dispara ao digitar

- **"Gerar área de estudo"** (custo baixo: um `st_buffer`) desenha o polígono no mapa e mostra a área em km². Com polígono pronto, o rótulo muda para "Carregar área de estudo", porque não há buffer a aplicar.
- **"Analisar"** (custo alto: ~20 consultas + rasters) roda os temas. Fica desabilitado até existir uma área de estudo.
- **Por que separar:** um `reactive()` sobre o campo de distância dispararia a cada tecla (`2`, `2,`, `2,5`), gerando buffers com valores inválidos e análises repetidas. A separação também deixa barato testar várias distâncias, que era o motivo de trazer o buffer para dentro do app, e expõe erro de digitação (25 em vez de 2,5) no mapa antes de pagar as consultas.
- **Implementação:** `eventReactive(input$gerar, ...)` para a área de estudo e `eventReactive(input$analisar, ...)` para os resultados. A validação da distância fica em um `reactive()` separado, com `validate(need(x > 0, ...))`, que avisa no campo enquanto a pessoa digita sem calcular nada. Um `observeEvent(area_estudo(), { registro(list()) })` descarta a síntese anterior quando a área muda.
- **Campo de distância:** `numericInput` não serve, porque devolve `NA` para `2,5`. Usar `textInput` com parsing (`str_replace(",", ".")` + `as.numeric`) ou `shinyWidgets::autonumericInput`, que já trata o formato pt-BR.

### Rasters no SQL Server: tiles GeoTIFF

- **Por que não o raster de geodatabase:** o raster de geodatabase do ArcGIS guarda os pixels em blocos de formato proprietário, que o R não lê.
- **Formato:** uma tabela comum por raster, com uma linha por tile de 1024 × 1024 pixels. Colunas: `tile_id`, `md5`, `Shape` (extensão do tile, SRID 4674) e `tif` (`varbinary(max)` com um GeoTIFF completo, `INT1U`, compressão DEFLATE). A tabela tem índice espacial em `Shape`.
- **NoData:** o arquivo do MapBiomas não define NoData. Na carga, o 0 (fora do Brasil e mar aberto) vira NoData, e os tiles só com NoData não são gravados. No app, o percentual por classe é calculado só sobre os pixels com dado (decisão de 11/11/2026): como os tiles vazios não estão no banco, contar os pixels sem dado daria resultados diferentes do raster original em áreas com mar aberto.
- **Pixels:** gravados no CRS original do MapBiomas (WGS 84), sem reprojeção, para não reamostrar as classes. Só o `Shape` é convertido para 4674.
- **Carga:** `data-raw/carga_mapbiomas_col11_2025.R`. Resultado da carga da Coleção 11 (2025): ~9.700 tiles, ~660 MB de GeoTIFF, todos com MD5 conferido. O raster equivalente em geodatabase, sem compressão, ocupa cerca de 20 GB.
- **Leitura:** `contar_raster_bd()` (`R/fct_raster_bd.R`) busca os tiles que intersectam o polígono da área de estudo, monta um mosaico virtual (VRT) e conta os pixels por classe com `crop(mask = TRUE, touches = FALSE)` + `freq()`. Validada em 11/11/2026 contra o `.tif` original em quatro áreas (corredores, litoral e canto entre tiles), com contagens idênticas.
- **Contagem no `terra`, não `extract`:** num corredor de 10,5 milhões de pixels, o `extract` + `count` levou 28,6 s no `.tif` local, contra 7,7 s do `crop` + `mask` + `freq`. A regra `touches = FALSE` (pixel entra se o centro está na área) é a mesma do `extract`; com `touches = TRUE`, o padrão do `mask`, entram ~0,2% a mais de pixels, os da borda. As duas formas diferiram em 1 pixel em 10,5 milhões, um empate de centro sobre a borda.
- **Módulo:** `mod_raster_bd` (`R/mod_raster_bd.R`), genérico para qualquer raster de classes em tiles no BD (decisão de 12/11/2026: o `mod_uso_solo` foi renomeado e generalizado, em vez de ganhar uma cópia para a declividade). Recebe `tabela`, `legenda` (`class_id`, `descricao`, `color` e colunas extras a exibir), `tema` (nome usado nas mensagens), `ordem` ("percentagem" decrescente ou "classe", a ordem da legenda) e `todas_classes` (inclui com 0 as classes ausentes na área). A legenda é preparada no `app_server.R`.
- **Outros softwares:** ArcGIS e QGIS enxergam a tabela só como polígonos (o contorno dos tiles). Ela é feita para o app.
- **FME:** os writers de SQL Server do FME não gravam raster. Se a atualização passar para o FME, o caminho é `RasterTiler` + `RasterExtractor` (GeoTIFF) + writer MSSQL, mantendo a mesma estrutura de tabela.

### Legendas do MapBiomas: todas as coleções numa tabela

- **Estrutura:** `legenda_mapbiomas` empilha as legendas de todas as coleções, com as colunas `colecao`, `class_id`, `level`, `descricao` e `color` (decisão de 10/11/2026, revista em 11/11/2026: saiu `descricao_en`, que nenhuma das legendas guardadas tem). Cada coleção mantém a estrutura da Coleção 10. As coleções antigas não são apagadas, para permitir análises comparativas entre versões.
- **Fontes:** os CSVs ficam em `data-raw/legendas_mapbiomas/`, um por coleção (`colecao_<n>.csv`), todos no mesmo formato (`class_id`, `level`, `descricao`, `color`, UTF-8), e são permanentes. A Coleção 10 foi exportada do `.rda` anterior. A Coleção 11 foi montada a partir do PDF oficial (de 13/08/2026), porque o CSV oficial só tem as 33 classes finais, sem nível, e tem erros de grafia. `data-raw/atualizacao_legenda.R` lê todos os `colecao_<n>.csv` da pasta, sem download, confere e gera o `.rda`.
- **Coleção 11 (montada em 11/11/2026):** 41 classes (33 finais e 8 agregadoras), com `level` de 1 a 4, nomes e cores do PDF, na ordem hierárquica dele. Na classe 22, mantida a grafia da Coleção 10, "Área não Vegetada" (o PDF usa "não vegetada"). Em relação à Coleção 10: 5 classes novas (7, 77, 84, 75, 91), 1 removida (27, "Não observado"), 1 renomeada (50, "Restinga Herbácea ou Arbustiva") e cores diferentes nas classes 1, 6, 10, 14, 26, 29 e 50 (29 e 50 trocaram de cor entre si).
- **Uso no app:** o `app_server.R` filtra a `legenda_mapbiomas` pela coleção configurada (`mapbiomas_colecao` no `golem-config.yml`) e passa o resultado ao `mod_raster_bd`. Uma legenda vazia (coleção sem legenda) impede a análise, com mensagem.
- **Nova coleção (provisório):** montar o `colecao_<n>.csv` no formato padrão a partir da legenda oficial, salvar na pasta, rodar o script e trocar a tabela e a coleção no `golem-config.yml`. Esse fluxo ainda exige publicar o app a cada coleção (ver "Versão do MapBiomas fixa na configuração", em Adiado).

### Declividade: Topodata SC

- **Alternativa descartada:** um raster de declividade de ~105 m, sem legenda nem metadados e com áreas terrestres sem dado, com as mesmas 6 classes Embrapa.
- **Fonte escolhida:** Topodata SC (INPE), declividade em 6 classes Embrapa (1999), ~30 m (1"), WGS 84, em 556 folhas de 1° × 1,5° no catálogo STAC `topodata-1`. Deriva do SRTM (2000), refinado de 90 m para 30 m. Resolução ~3,5 vezes maior que a alternativa.
- **Teste na folha 22S435 (Rio de Janeiro, 11/11/2026):** % de pixels por classe.

  | Classe | Alternativa (~105 m) | Topodata SC (~30 m) |
  |---|---|---|
  | 1 Plano | 18,2 | 14,3 |
  | 2 Suave ondulado | 12,9 | 11,3 |
  | 3 Ondulado | 22,5 | 13,0 |
  | 4 Forte ondulado | 35,3 | 37,6 |
  | 5 Montanhoso | 9,8 | 20,6 |
  | 6 Escarpado | 1,3 | 3,2 |

  O pixel grosso faz média do relevo e suaviza as encostas: na alternativa, a área montanhosa é metade da do Topodata. A ordem das classes bate nos dois.
- **Mar e fora do Brasil:** o Topodata não define NoData, e todo pixel tem classe, inclusive o mar. Na folha de teste, nos pixels de mar, o Topodata deu 60% Plano, 33% Suave ondulado e o resto em classes íngremes: é o ruído do SRTM sobre a água. Na carga, cada tile é mascarado com os limites municipais, com a regra do centro do pixel (`touches = FALSE`). O que fica fora vira NoData, e os tiles vazios não são gravados.
- **Grade:** a largura do pixel e a origem variam um pouco entre folhas (até ~0,0001°, ~11 m, menos de meio pixel). As folhas são unidas num VRT em grade fixa de 1" (`-tr 1/3600 -tap -r nearest`), com `-vrtnodata 255` para que área sem folha seja NoData, e não 0.
- **Legenda:** `legenda_declividade` (`data-raw/legenda_declividade.csv` → `data-raw/legenda_declividade.R`), com `class_id`, `descricao`, `lim_inf`, `lim_sup` (em %, intervalo [lim_inf, lim_sup)) e `color`. Nomes e limites do sistema Embrapa (0–3, 3–8, 8–20, 20–45, 45–75, >75%). A simbologia oficial do Topodata só tem rótulos "1" a "6" e tons de cinza, então as cores seguem uma rampa verde → vermelho escuro.
- **Carga:** mesma estrutura de tabela do MapBiomas. Por causa da máscara, os tiles são gerados um a um, na mesma grade e numeração do `makeTiles`. O script de carga tem um modo teste (`modo_teste = TRUE`), que faz o caminho inteiro só com a folha de teste numa tabela `TESTE_` e confere a leitura com `contar_raster_bd()`.
- **Teste de carga (11/11/2026, folha 22S435):** 28 tiles, 2,7 MB (~100 KB por tile), sem binário corrompido nem geometria com problema. A máscara retirou 1,19 milhão de pixels (~6% da folha), quase todos de Plano e Suave ondulado: só 42 pixels de Escarpado saíram, sinal de que cortou o mar e não as encostas. Numa área de teste de 2 km em torno de uma linha que cruza baixada, serra e costa, a contagem lida do banco por `contar_raster_bd()` foi idêntica à dos tiles locais nas 6 classes (893.126 pixels), desde que a referência local use a mesma geometria da função (`st_union()` + `st_make_valid()`): sem isso, 2 pixels com centro sobre a borda trocaram de lado.
- **No app (12/11/2026):** aba "Declividade" em Meio Físico, com o `mod_raster_bd`. A tabela traz sempre as 6 classes, na ordem Plano → Escarpado, com 0 nas ausentes e a coluna `faixa` (ex.: "0 a 3%", "> 75%"), montada no `app_server.R` a partir de `lim_inf` e `lim_sup`. Falta testar no app em execução.
- **Carga completa (11/11/2026):** ~9.200 tiles, ~760 MB de GeoTIFF, todos com MD5 conferido, sem geometria com problema, com índice espacial. A gravação no banco levou 11 minutos.

### Geometrias inválidas para o s2: filtro de interseção com GEOS

- **Problema (12/11/2026):** num corredor de teste, a aba Processos Minerários quebrou no `st_filter` do `mod_banco` com `Loop 0 is not valid: Edge ... has duplicate vertex with edge ...`. Com coordenadas geográficas (4674), o `sf` usa o s2 como motor, e o s2 valida cada polígono ao montá-lo, com regras mais rígidas que as do SQL Server e do GEOS. O aviso `sf layer has inconsistent datum` que aparece junto só indica que o s2 trata SIRGAS 2000 como WGS 84 e não afeta o resultado.
- **Diagnóstico:** numa região de teste com ~46 mil processos, 86 são inválidos para o s2 e todos são válidos para o SQL Server (`STIsValid() = 1`):
  - 81 com vértice duplicado: vértices quase iguais, que no plano são distintos e no s2 viram o mesmo ponto, fazendo o anel se tocar.
  - 5 com arestas vizinhas que se cruzam: provavelmente pontas finas que só se cruzam na geometria esférica.
- **Correções testadas, sem sucesso:**
  - `st_make_valid()` com o s2 ligado (internamente, `s2::s2_rebuild()`): parte das geometrias continuou inválida para o s2.
  - Arredondar as coordenadas a 1e-7° (~1 cm, com `st_as_binary(precision = 1e7)`) e reparar com o GEOS (`sf_use_s2(FALSE)` + `st_make_valid()`): ainda restaram inválidos para o s2. O reparo no plano gera geometrias válidas pelas regras OGC que o s2 continua recusando.
  - `MakeValid()` no SQL Server não mudaria nada, porque o banco considera esses polígonos válidos.
- **Decisão:** no `mod_banco`, a interseção com a área de estudo é feita com o GEOS. O `reactive` desliga o s2 só durante o `st_filter` e restaura o valor anterior com `on.exit()`. Os dados não são alterados. Para um predicado de interseção, o cálculo no plano, em graus, dá na prática o mesmo resultado que o esférico; só haveria diferença com arestas de centenas de quilômetros. Buffer e áreas continuam geodésicos, com o s2.

  ```r
  tema_corredor <- reactive({
    req(shp_corredor(), !is.null(base_tema))
    s2_antes <- sf::sf_use_s2(FALSE)
    on.exit(sf::sf_use_s2(s2_antes), add = TRUE)
    sf::st_filter(base_tema, shp_corredor(), .predicate = sf::st_intersects)
  })
  ```

- **Fora do escopo:** o `mod_sobreposicao` não recebe o ajuste, porque será descontinuado com a migração de todos os temas para o BD. Pelo mesmo motivo, não foi criada uma função genérica de filtro (ex.: `filtrar_corredor()`) por ora.
- **Como diagnosticar outro tema:** trazer só o identificador e a geometria em WKB (`Shape.STAsBinary()`), com filtro espacial no servidor por um retângulo (`Shape.STIntersects(geometry::STGeomFromText('<wkt>', 4674)) = 1`). Converter com `st_as_sfc(structure(lapply(wkb, as.raw), class = "WKB"), crs = 4674)` e rodar `s2::s2_is_valid_detail()`. O `STIsValid()` do SQL Server não serve como teste, porque aceita essas geometrias.

### Envio da área de estudo: conferência do .zip (13/11/2026)

- **Problema:** o `mod_corredor` tentava ler qualquer `.zip` e derrubava a sessão quando não havia shapefile dentro. Depois de um envio inválido, a mensagem de erro continuava na tela mesmo após um envio válido.
- **Leitura:** `ler_corredor()` (`R/fct_corredor.R`) confere o `.zip` antes de ler, com uma mensagem por problema: arquivo que não é `.zip` ou está corrompido; nenhum `.shp` ou mais de um; falta de `.dbf`, `.shx` ou `.prj` (sem `.prj`, a reprojeção quebrava); shapefile ilegível ou sem feições; `.prj` não reconhecido; geometria que não é polígono; mais de uma feição; feição sem geometria. O shapefile pode estar numa pasta dentro do `.zip`, e os arquivos de controle do macOS (`__MACOSX/`, `._*`) são ignorados. Os erros previstos têm a classe `erro_corredor`; qualquer outro erro vira uma mensagem genérica, sem derrubar a sessão.
- **Mensagem:** numa caixa própria acima do mapa, substituída a cada envio e apagada quando o envio dá certo. O mapa nunca recebe erro: mostra o Brasil sem corredor e o polígono com corredor. A causa da mensagem persistente não foi reproduzida; a hipótese é que o erro ia para o próprio `leafletOutput`, que não o limpava ao renderizar de novo.
- **Envio inválido descarta o corredor anterior:** o mapa volta ao Brasil, e as tabelas dos temas ficam vazias (param no `req()`) e saem da planilha exportada até o próximo envio válido. Motivo: não manter na tela resultados de um arquivo que não é o último enviado. Para manter o anterior, trocar `corredor(lido$sf)` por `if (!is.null(lido$sf)) corredor(lido$sf)` no `mod_corredor.R`.
- **Provisório:** vale até a reestruturação da entrada (`.kml/.kmz`, `.gpkg`, `.gdb` e traçado com buffer, ver "Entrada" e "Fluxo do buffer"). A conferência do shapefile deve ser reaproveitada lá.
- Falta testar no app em execução.

## Adiado (implementação futura)

- **Aba de metadados:** temas consultados e, para cada um, a fonte em formato de referência bibliográfica, para o tópico equivalente da NT.
- **Resumos por tema:** agregações (summarise) e agrupamentos descritivos. As regras serão definidas tema a tema.
- **Faixa de proximidade por tema:** a decisão depende do feedback dos usuários.
- **Comparação lado a lado** de distâncias de buffer.
- **Formato numérico** (vírgula decimal, casas, unidades nos cabeçalhos): ainda não definido.
- **Servidor e concorrência:** falta definir se o app roda em Shiny Server Open Source (um processo R por app) ou Posit Connect. A proposta é rodar a análise com `ExtendedTask` + `mirai`, com a síntese preenchida tema a tema.
- **Reatividade do protótipo:** o protótipo v2 simula estados prontos, sem reatividade real. O fluxo de dois botões descrito em "Decidido" ainda não está refletido nele.
- **MapBiomas no servidor Shiny:** a leitura dos tiles foi validada na máquina de desenvolvimento. Falta o teste no servidor (permissão de leitura da conta de serviço na tabela e escrita na pasta temporária).
- **Atualização anual do MapBiomas:** definir se a carga de cada nova coleção continua pelo script em R ou passa para o FME.
- **Geometrias válidas na carga (registrado em 12/11/2026):** corrigir na origem os polígonos inválidos para o s2. O caminho a testar é arredondar as coordenadas (7 ou 8 casas decimais) antes da validação com reparo, mas o teste no R indica que o reparo no plano não basta para o s2. O critério de aceite da carga é a verificação com o s2 (zero inválidos, como em "Como diagnosticar outro tema"), não o `STIsValid()` do SQL Server. Enquanto isso, o filtro com GEOS no `mod_banco` mantém o app funcionando.
- **Versão do MapBiomas fixa na configuração (registrado em 11/11/2026):** a tabela de tiles e a coleção ficam no `golem-config.yml`. A configuração faz parte do pacote, então cada nova coleção ainda exige publicar o app de novo. A meta é que uma nova coleção entre só com a carga dos dados. Ideias a avaliar:
  - **Catálogo de rasters no BD:** uma tabela com tema, coleção, ano de referência, tabela de tiles, data da carga e se a versão está vigente. A carga registra a linha, e o app usa a versão vigente. As versões antigas continuam no banco, o que abre caminho para escolher a versão na interface e para análises comparativas.
  - **Legenda no BD, junto do catálogo:** hoje a legenda é um `.rda` dentro do pacote, então uma legenda nova também exige publicar o app. No banco, raster e legenda seriam atualizados juntos.
  - **Questões em aberto:** quem atualiza o catálogo (script em R ou FME); como garantir que todo valor de pixel do raster tenha classe na legenda da mesma coleção; o que o app faz se não houver versão vigente.
- **Hierarquia explícita da legenda (registrado em 11/11/2026):** a legenda só tem `level`; a classe-mãe de cada classe depende da ordem das linhas no CSV. Para resumos por grupo (ex.: % de Agropecuária), avaliar uma coluna explícita (`class_id_pai` ou o código hierárquico do PDF, ex.: `3.2.1.1`). Atenção: o PDF da Coleção 11 numera a classe 48 como 3.2.1.4, mas ela é filha de Lavoura Perene (3.2.2.4).
- **Declividade a partir do ANADEM (registrado em 11/11/2026):** o ANADEM (ANA + IPH/UFRGS, 2024) é um modelo digital de terreno de 30 m derivado do Copernicus GLO-30, com remoção do viés da vegetação. O SRTM, base do Topodata, é um modelo de superfície: nas bordas de floresta, a altura do dossel aparece como declividade. Adotar o ANADEM exige calcular a declividade (`terra::terrain`) e gravar o % em `INT1U` com `floor()`. A `legenda_declividade` já tem os limites em %, então serve para classificar esse dado contínuo. Antes de decidir, comparar o % por classe nos dois dados em corredores reais, ao menos um em área de floresta.

## Inventário de temas

As tabelas de cada tema no BD são definidas na seção `temas` do `inst/golem-config.yml`.

| Grupo | Tema | No app | Origem | Situação |
|---|---|---|---|---|
| Infraestrutura | Municípios | sim | BD | ok |
| Infraestrutura | Áreas Urbanas | sim | BD | ok (pouco usado) |
| Infraestrutura | Linhas de Transmissão | sim | BD | ok |
| Infraestrutura | Subestações | sim | BD | ok |
| Infraestrutura | Usinas | sim | BD | ok |
| Infraestrutura | Gasoduto Transporte | sim | BD | ok |
| Infraestrutura | Dutos Escoamento | sim | BD | ok |
| Infraestrutura | Gasoduto Distribuição | sim | BD | ok |
| Transportes | Rodovias (OSM) | sim | BD | ok (pesado) |
| Transportes | Aeródromos | sim | BD | ok |
| Transportes | Ferrovias | sim | BD | ok |
| Geração | UHE, PCH, CGH | não | ? | mapear |
| Geração | UTE / UFV / Eólicas (operação e planejadas) | não | ? | mapear |
| Geração | Reservatório de UHE planejada | não | ? | mapear |
| Uso do solo | MapBiomas (Coleção 11, 2025) | sim | BD (tiles GeoTIFF) | falta testar no servidor |
| Uso do solo | Bioma | não | ? | mapear |
| Meio físico | Hidrografia (simplificada) | sim | geodatabase | falta view no BD |
| Meio físico | Cavernas | sim | BD | ok |
| Meio físico | Declividade (Topodata SC) | sim | BD (tiles GeoTIFF) | falta testar no app e no servidor |
| Meio físico | Relevo | não | ? | mapear |
| Processos minerários | Processos Minerários | sim | BD | ok (pesado; polígonos inválidos para o s2, contornado com filtro GEOS) |
| Áreas protegidas | Terras Indígenas | sim | BD | ok |
| Áreas protegidas | Terras Quilombolas | sim | BD | ok |
| Áreas protegidas | Projetos de Assentamento | sim | BD | ok |
| Áreas protegidas | Unidades de Conservação | sim | BD | ok |
| Áreas protegidas | UC (base complementar) | sim | BD | erro: WGS 84, reprojetar |
| Áreas protegidas | RPPN | sim | BD | ok |
| Áreas protegidas | Sítios Arqueológicos | sim | BD | ok |

"Mapear" significa identificar a view ou layer de origem. Na coluna "Origem", "?" quer dizer que a origem ainda não é conhecida.
