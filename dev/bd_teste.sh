#!/usr/bin/env bash
# Banco de teste local: SQL Server 2022 (Developer) em Docker, só para os
# testes de integração (tests/testthat/test-integracao_bd.R). Não é o banco de
# produção e não tem dados reais: os testes criam tabelas TESTE_ sintéticas.
#
# Uso: bash dev/bd_teste.sh
# Pré-requisitos: Docker e o driver ODBC 18 (msodbcsql18). A imagem do SQL
# Server exige aceitar a licença da Microsoft (ACCEPT_EULA=Y).
#
# Grava a conexão em ~/.Renviron (fora do repositório), nas variáveis
# ANALISE_BD_TESTE_*. A senha é gerada na primeira execução e fica em
# ~/.analise_bd_teste.
set -euo pipefail

CONTAINER=analise_bd_teste
IMAGEM=mcr.microsoft.com/mssql/server:2022-latest
BANCO=analise_teste
SEGREDO="$HOME/.analise_bd_teste"

# Docker (em containers sem systemd, o daemon é iniciado aqui)
if ! docker info >/dev/null 2>&1; then
  (dockerd >/tmp/dockerd.log 2>&1 &)
  for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
fi

# Senha local, gerada uma vez
if [ ! -f "$SEGREDO" ]; then
  umask 077
  echo "ANALISE_BD_TESTE_SENHA=Teste_$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 16)9a" > "$SEGREDO"
fi
# shellcheck disable=SC1090
. "$SEGREDO"

# Container: cria na primeira vez, depois só inicia
if ! docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  docker run -d --name "$CONTAINER" -e ACCEPT_EULA=Y -e MSSQL_PID=Developer \
    -e "MSSQL_SA_PASSWORD=$ANALISE_BD_TESTE_SENHA" -p 127.0.0.1:1433:1433 "$IMAGEM" >/dev/null
else
  docker start "$CONTAINER" >/dev/null
fi

sqlcmd() {
  docker exec "$CONTAINER" /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa \
    -P "$ANALISE_BD_TESTE_SENHA" -b "$@"
}
for _ in $(seq 1 60); do sqlcmd -Q "SELECT 1" >/dev/null 2>&1 && break; sleep 2; done
sqlcmd -Q "IF DB_ID('$BANCO') IS NULL CREATE DATABASE $BANCO;" >/dev/null

# Conexão para o R (testes de integração)
DRIVER=$(ls /opt/microsoft/msodbcsql18/lib64/libmsodbcsql-18.*.so.* | head -n 1)
touch "$HOME/.Renviron"
sed -i '/^ANALISE_BD_TESTE_/d' "$HOME/.Renviron"
cat >> "$HOME/.Renviron" <<EOF
ANALISE_BD_TESTE_DRIVER=$DRIVER
ANALISE_BD_TESTE_SERVER=127.0.0.1,1433
ANALISE_BD_TESTE_DATABASE=$BANCO
ANALISE_BD_TESTE_UID=sa
ANALISE_BD_TESTE_SENHA=$ANALISE_BD_TESTE_SENHA
EOF

echo "Banco de teste pronto: $BANCO em 127.0.0.1,1433 (SQL Server 2022)."
