#' Legenda de declividade
#'
#' Classes de declividade do sistema Embrapa (1999), na codificação do raster
#' Topodata SC (INPE), gravado em tiles no SQL Server. Os limites em \% permitem
#' também classificar uma declividade contínua com a mesma tabela.
#'
#' \describe{
#'   \item{class_id}{Código da classe, o valor do pixel no raster (1 a 6).}
#'   \item{descricao}{Nome da classe (ex.: Plano, Escarpado).}
#'   \item{lim_inf}{Limite inferior da classe, em \%, incluído no intervalo.}
#'   \item{lim_sup}{Limite superior da classe, em \%, fora do intervalo.
#'     `NA` na última classe (Escarpado, acima de 75\%).}
#'   \item{color}{Cor da classe em hexadecimal (#rrggbb), do verde (Plano) ao
#'     vermelho escuro (Escarpado).}
#' }
#'
#' @format Um \code{tibble} com 6 linhas e 5 colunas.
#'   Gerado por \code{data-raw/legenda_declividade.R}.
#' @source \url{https://data.inpe.br/dados/topodata/}
"legenda_declividade"
