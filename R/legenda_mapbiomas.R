#' Legenda MapBiomas
#'
#' Legendas das classes de cobertura e uso da terra do MapBiomas, uma por
#' coleção, empilhadas numa só tabela. As coleções anteriores são mantidas para
#' permitir análises comparativas entre versões. Filtre por `colecao` antes de
#' cruzar com um raster: o mesmo `class_id` aparece uma vez em cada coleção.
#'
#' As linhas de cada coleção seguem a ordem hierárquica da legenda oficial:
#' cada classe agregadora vem antes das suas classes filhas.
#'
#' \describe{
#'   \item{colecao}{Número da coleção do MapBiomas (ex.: 10, 11).}
#'   \item{class_id}{Código da classe, o valor do pixel no raster.}
#'   \item{level}{Nível hierárquico da classe, de 1 (agregadora mais geral,
#'     ex.: Floresta) a 4 (ex.: Soja). Os pixels do raster têm sempre a classe
#'     final; as agregadoras só servem para resumir por grupo.}
#'   \item{descricao}{Nome da classe em português.}
#'   \item{color}{Cor oficial da classe, em hexadecimal (#rrggbb).}
#' }
#'
#' @format Um \code{tibble} com uma linha por classe e coleção, e 5 colunas.
#'   Gerado por \code{data-raw/atualizacao_legenda.R}.
#' @source \url{https://brasil.mapbiomas.org/codigos-de-legenda/}
"legenda_mapbiomas"
