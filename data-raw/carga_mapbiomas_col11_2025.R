# =============================================================================
# CARGA COMPLETA: MapBiomas Coleção 11 (2025) no SQL Server, em tiles GeoTIFF
# =============================================================================
#
# Pensado para um banco de PRODUÇÃO. Este script:
#   - cria UMA tabela nova e só insere nela;
#   - não tem nenhum comando que apague ou altere tabelas;
#   - grava em lotes de 100 tiles por transação: se um lote falhar, o SQL
#     Server desfaz só aquele lote e o script para;
#   - pode ser retomado: ao rodar de novo, pula os tiles que já estão na tabela.
#
# Conexão: variáveis de ambiente ANALISE_BD_DRIVER, ANALISE_BD_SERVER e
# ANALISE_BD_DATABASE (ver .Renviron.exemplo). Usuário e senha são pedidos
# na hora, e nunca ficam no código.
#
# Rode etapa por etapa (Ctrl+Enter), conferindo cada resultado. Não use source().
#
#   Etapa 0  Configuração, conexão e verificações (somente leitura)
#   Etapa 1  Gerar todos os tiles no disco local (não toca no banco)
#   Etapa 2  Piloto: criar a tabela e gravar os 100 primeiros tiles
#   Etapa 3  Gravar o restante
#   Etapa 4  Validação final e índice espacial

library(terra)
library(sf)
library(DBI)


# 0. Configuração, conexão e verificações --------------------------------------

tif          <- "C:/temp/brazil_coverage-col11_2025.tif"   # cópia local
pasta_tiles  <- "C:/temp/tiles_col11_2025"                 # ~1,5 GB; precisa persistir
esquema      <- "dbo"
tabela       <- "MAPBIOMAS_TILES"                          # mesmo nome de temas$mapbiomas no golem-config.yml
srid         <- 4674
tamanho_tile <- 1024
tamanho_lote <- 100

con <- dbConnect(odbc::odbc(),
                 Driver   = Sys.getenv("ANALISE_BD_DRIVER", "ODBC Driver 18 for SQL Server"),
                 Server   = Sys.getenv("ANALISE_BD_SERVER"),
                 Database = Sys.getenv("ANALISE_BD_DATABASE"),
                 uid      = rstudioapi::askForPassword("Usuário do banco"),
                 pwd      = rstudioapi::askForPassword("Senha"))

alvo     <- Id(schema = esquema, table = tabela)
alvo_sql <- dbQuoteIdentifier(con, alvo)

# 0.1 Permissões: as duas devem ser 1
permissoes <- dbGetQuery(con, "
  SELECT HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'CREATE TABLE') AS pode_criar_tabela,
         HAS_PERMS_BY_NAME(?, 'SCHEMA', 'ALTER')                  AS pode_usar_esquema",
  params = list(esquema))
permissoes
stopifnot(permissoes$pode_criar_tabela == 1, permissoes$pode_usar_esquema == 1)

# 0.2 Espaço: o arquivo de dados do banco vai crescer ~1,2 GB.
#     Confira o incremento de crescimento e o espaço livre no disco do servidor.
dbGetQuery(con, "
  SELECT name, type_desc,
         CASE WHEN is_percent_growth = 1 THEN CAST(growth AS VARCHAR(10)) + ' %'
              ELSE CAST(CAST(growth AS BIGINT) * 8 / 1024 AS VARCHAR(20)) + ' MB' END AS crescimento
  FROM sys.database_files")

# Pode falhar por falta de permissão; nesse caso, confirme o espaço livre com o DBA.
tryCatch(
  dbGetQuery(con, "
    SELECT DISTINCT vs.volume_mount_point AS disco,
           vs.available_bytes / 1073741824 AS livre_gb
    FROM sys.database_files f
    CROSS APPLY sys.dm_os_volume_stats(DB_ID(), f.file_id) vs"),
  error = \(e) message("Sem permissão para ver o disco do servidor: ", conditionMessage(e))
)

# 0.3 Estado da tabela: FALSE na primeira execução, TRUE numa retomada
dbExistsTable(con, alvo)

# 0.4 Raster de origem
r <- rast(tif)
stopifnot(datatype(r) == "INT1U")
NAflag(r) <- 0   # o arquivo não define NoData; 0 = fora do Brasil / mar aberto
r


# 1. Gerar os tiles no disco local (não toca no banco) -------------------------
#    Leva uns 15 a 20 minutos. Se a pasta já tiver os tiles, pule o makeTiles.

dir.create(pasta_tiles, showWarnings = FALSE, recursive = TRUE)

if (length(list.files(pasta_tiles, "\\.tif$")) == 0) {
  tempo_tiles <- system.time(
    makeTiles(r, tamanho_tile,
              filename = file.path(pasta_tiles, "tile_.tif"),
              na.rm = TRUE,                # descarta tiles só com NoData
              datatype = "INT1U",
              gdal = "COMPRESS=DEFLATE")
  )
  print(tempo_tiles)
}

# Inventário dos tiles: o tile_id vem do número no nome do arquivo
tiles <- data.frame(arquivo = list.files(pasta_tiles, "^tile_\\d+\\.tif$", full.names = TRUE))
tiles$tile_id <- as.integer(sub("^tile_(\\d+)\\.tif$", "\\1", basename(tiles$arquivo)))
tiles$bytes   <- file.size(tiles$arquivo)
tiles <- tiles[order(tiles$tile_id), ]

# Conferências locais
nrow(tiles)                        # esperado: algo entre 9.000 e 10.500
sum(tiles$bytes) / 2^30            # GB; esperado: perto de 1
summary(tiles$bytes / 1024)        # KB por tile
stopifnot(!anyDuplicated(tiles$tile_id), all(tiles$bytes > 0))

# Amostra de 30 tiles: todos devem abrir, ser INT1U e ter pixels com dado
amostra <- sample(tiles$arquivo, 30)
stopifnot(all(sapply(amostra, \(f) datatype(rast(f)) == "INT1U")),
          all(sapply(amostra, \(f) global(rast(f), "notNA")[[1]] > 0)))

# Conferência visual: os tiles devem desenhar o contorno do Brasil
extensoes <- do.call(rbind, lapply(tiles$arquivo, \(f) as.vector(ext(rast(f)))))
plot(extensoes[, "xmin"], extensoes[, "ymin"], pch = ".", asp = 1,
     xlab = "longitude", ylab = "latitude", main = "Tiles com dado")


# 2. Piloto: criar a tabela e gravar os 100 primeiros tiles ----------------------

extensao_wkt <- function(arquivo) {
  as.vector(ext(rast(arquivo))) |>
    st_bbox(crs = st_crs(crs(r))) |>
    st_as_sfc() |>
    st_transform(srid) |>
    st_as_text(digits = 15)
}

# Grava um lote numa única transação: ou entra o lote inteiro, ou nada
gravar_lote <- function(lote) {
  dbWithTransaction(con, {
    for (i in seq_len(nrow(lote))) {
      dbExecute(con, glue::glue(
        "INSERT INTO {alvo_sql} (tile_id, md5, Shape, tif)
         VALUES (?, ?, geometry::STGeomFromText(?, {srid}), ?)"
      ), params = list(
        lote$tile_id[i],
        unname(tools::md5sum(lote$arquivo[i])),
        extensao_wkt(lote$arquivo[i]),
        blob::blob(readBin(lote$arquivo[i], "raw", lote$bytes[i]))
      ))
    }
  })
}

# Tiles que ainda não estão na tabela
pendentes <- function() {
  gravados <- dbGetQuery(con, glue::glue("SELECT tile_id FROM {alvo_sql}"))$tile_id
  tiles[!tiles$tile_id %in% gravados, ]
}

# Validação: todas as contagens de problema devem ser 0
validar <- function() {
  dbGetQuery(con, glue::glue(
    "SELECT COUNT(*)                                  AS tiles,
            SUM(DATALENGTH(tif)) / 1048576            AS mb,
            SUM(CASE WHEN LOWER(CONVERT(CHAR(32), HASHBYTES('MD5', tif), 2)) = md5
                     THEN 0 ELSE 1 END)               AS binarios_corrompidos,
            SUM(CASE WHEN Shape.STSrid = {srid} AND Shape.STIsValid() = 1
                     THEN 0 ELSE 1 END)               AS geometrias_com_problema
     FROM {alvo_sql}"
  ))
}

# 2.1 Criar a tabela (só se ainda não existir)
if (!dbExistsTable(con, alvo)) {
  dbExecute(con, glue::glue(
    "CREATE TABLE {alvo_sql} (
       tile_id INT            NOT NULL PRIMARY KEY,
       md5     CHAR(32)       NOT NULL,
       Shape   geometry       NOT NULL,
       tif     varbinary(max) NOT NULL)"
  ))
}
stopifnot(identical(dbListFields(con, alvo), c("tile_id", "md5", "Shape", "tif")))

# 2.2 Gravar o piloto e medir o tempo
piloto <- head(pendentes(), tamanho_lote)
tempo_piloto <- system.time(gravar_lote(piloto))
tempo_piloto

# 2.3 Validar o piloto: 100 tiles, 0 corrompidos, 0 geometrias com problema
v <- validar()
v
piloto_ok <- v$binarios_corrompidos == 0 && v$geometrias_com_problema == 0

# Estimativa para o restante, em minutos
tempo_piloto[["elapsed"]] / nrow(piloto) * nrow(pendentes()) / 60

# PARE AQUI. Confiram os números acima antes de seguir para a etapa 3.


# 3. Gravar o restante -----------------------------------------------------------
#    Se cair no meio: reconecte (etapa 0) e rode esta etapa de novo.

stopifnot(piloto_ok)

faltam <- pendentes()
lotes  <- split(faltam, ceiling(seq_len(nrow(faltam)) / tamanho_lote))
message(nrow(faltam), " tiles pendentes em ", length(lotes), " lotes.")

inicio <- Sys.time()
for (k in seq_along(lotes)) {
  gravar_lote(lotes[[k]])
  if (k %% 10 == 0 || k == length(lotes)) {
    message(sprintf("Lote %d de %d | %.1f min", k, length(lotes),
                    as.numeric(difftime(Sys.time(), inicio, units = "mins"))))
  }
}


# 4. Validação final e índice espacial -------------------------------------------

# 4.1 Esperado: 0 pendentes; tiles = nrow(tiles); 0 corrompidos; 0 com problema
nrow(pendentes())
v <- validar()
v
stopifnot(nrow(pendentes()) == 0, v$tiles == nrow(tiles),
          v$binarios_corrompidos == 0, v$geometrias_com_problema == 0)

# 4.2 Espaço ocupado no banco
dbGetQuery(con, glue::glue("EXEC sp_spaceused N'{esquema}.{tabela}'"))

# 4.3 Índice espacial (só depois da validação). BOUNDING_BOX cobre o raster inteiro.
bb <- as.vector(ext(r))
dbExecute(con, glue::glue(
  "CREATE SPATIAL INDEX SIX_{tabela} ON {alvo_sql}(Shape)
   WITH (BOUNDING_BOX = ({floor(bb[['xmin']])}, {floor(bb[['ymin']])},
                         {ceiling(bb[['xmax']])}, {ceiling(bb[['ymax']])}))"
))

dbDisconnect(con)

# Depois de tudo conferido, a pasta de tiles local pode ser apagada à mão:
# unlink(pasta_tiles, recursive = TRUE)
