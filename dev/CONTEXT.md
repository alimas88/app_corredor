# analise.corredor

Apoio à caracterização socioambiental de empreendimentos de transmissão (Relatório R1): cruza a área de estudo de um empreendimento com os temas da base geográfica e sintetiza as interferências.

## Empreendimento e geometria

**Linha de Transmissão (LT)**:
Empreendimento representado por uma linha. Inclui bipolos de corrente contínua, que podem ter milhares de km.

**Subestação (SE)**:
Empreendimento representado por um ponto.

**Traçado**:
Geometria enviada pelo usuário que representa o empreendimento: linha (LT) ou ponto (SE). Quando vários empreendimentos são analisados juntos, o analista envia uma só geometria (ex.: ponto central), e não um traçado por empreendimento.
_Avoid_: eixo, shape de entrada

**Distância de buffer**:
Distância, em metros, aplicada ao traçado para gerar a área de estudo; única para todos os temas.

**Área de estudo**:
Polígono único cruzado com os temas, gerado por buffer do traçado ou enviado pronto. Uma análise trata uma área de estudo por vez.
_Avoid_: área de análise, polígono de análise

**Corredor**:
Área de estudo de uma LT; termo usado nos textos do R1.

## Análise e saída

**Tema**:
Base geográfica cruzada com a área de estudo (ex.: Terras Indígenas, Processos Minerários, MapBiomas).
_Avoid_: camada, layer, base

**Interferência**:
Feição de um tema que intersecta diretamente a área de estudo. Não há busca por proximidade além dela.
_Avoid_: sobreposição, cruzamento (como substantivo do resultado)

**Situação do tema**:
Resultado da verificação de um tema: com interferência, sem interferência ou não verificado (a consulta falhou). "Não verificado" nunca equivale a "sem interferência".

**Tabela de resultado**:
Todas as interferências de um tema, feição a feição, com os atributos do tema.
_Avoid_: tabela bruta

**Resumo do tema**:
Tabela derivada da tabela de resultado para apoiar a redação: agregação (ex.: % da área de estudo por classe do MapBiomas) ou agrupamento descritivo (ex.: processos minerários por fase e substância). As regras de cada tema ainda serão definidas.

**Síntese das interferências**:
Documento Word de apoio gerado pelo app: uma tabela por tema, identificada pelo nome do tema, mais a situação dos demais temas. Não é a nota técnica.

**Relatório R1**:
Nota técnica de caracterização socioambiental redigida pela equipe, usando a síntese como apoio.

**Planilha de conferência**:
Excel com uma aba por tema, para verificar interferências sem reabrir o app.
_Avoid_: relatório (para o xlsx)
