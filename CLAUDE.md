# analise.corredor

Pacote R com app Shiny (`golem`) que cruza a área de estudo de um empreendimento de
transmissão com temas de uma base geográfica, para apoiar a caracterização
socioambiental do Relatório R1.

## Contexto do projeto

- Vocabulário do domínio: @dev/CONTEXT.md
- Decisões, pendências e inventário de temas: @dev/DECISOES.md

Use os termos do vocabulário (área de estudo, traçado, interferência, situação do tema,
tabela de resultado, resumo do tema) no código, na UI e nas conversas. Ao resolver um
termo novo ou fechar uma decisão, atualize o arquivo correspondente na mesma sessão.

## Convenções de código

- Pacote em `golem`: módulos em `R/mod_*.R`, funções em `R/fct_*.R`, utilitários em `R/utils.R`.
- Buscar o ponto ótimo entre genericidade e especificidade; reutilizar em vez de duplicar.
- Tidyverse sempre que possível, com as funções mais atuais e estáveis.
- Dados espaciais com `sf`, `terra` e `leaflet`.
- UI em `bslib`.
- Cálculos de buffer e área são geodésicos, em SIRGAS 2000 (EPSG:4674).
- Conexão ao banco e nomes das tabelas ficam no `inst/golem-config.yml` e em
  variáveis de ambiente (`.Renviron`), nunca no código.
- Rasters ficam no SQL Server em tiles GeoTIFF e são lidos com `contar_raster_bd()`
  (`R/fct_raster_bd.R`). As cargas são scripts em `data-raw/`. O servidor Shiny não
  acessa unidades de rede, então nenhum tema novo deve depender de arquivo em disco.
- O banco é de produção e não há banco de teste: scripts de carga não apagam nem
  alteram tabelas, e todo teste de escrita usa tabela com prefixo `TESTE_`.

## Referência visual

`dev/prototipos/prototipo_sintese.html` é um protótipo descartável da UI (dados de
exemplo, não é código de produção).
