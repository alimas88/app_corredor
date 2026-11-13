#' Corredor
#'
#' Um objeto \code{sf} com um corredor fictício, usado para testar as análises
#' de sobreposição. Não representa nenhum empreendimento real.
#'
#' Este objeto é um \code{simple feature collection} contendo 1 feição (polygon)
#' com 3 colunas:
#'
#' \describe{
#'   \item{id}{Identificador único do corredor.}
#'   \item{BUFF_DIST}{Distância de buffer associada ao corredor, em metros.}
#'   \item{geometry}{Geometria do corredor em formato de polígono (CRS: SIRGAS 2000).}
#' }
#'
#' @format Um objeto \code{sf} com 1 feição e 3 variáveis.
#' @source Dado fictício, gerado por \code{data-raw/corredor.R}.
"corredor"
