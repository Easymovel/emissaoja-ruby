# frozen_string_literal: true

# Cliente oficial em Ruby da API do emissaoja (https://emissaoja.com.br/docs/): emissão de NFS-e no Emissor
# Nacional com o CNPJ e a senha do portal, sem certificado digital, para MEI e empresas do Simples Nacional.
#
#   require "emissaoja"
#
#   ej = Emissaoja::Cliente.new(chave: ENV["EMISSAOJA_KEY"], base_url: Emissaoja::BASE_SANDBOX)
#   r = ej.notas.emitir("pedido-0001", tomador_tipo: "pj", tomador_id: id, valor: 1500, descricao: "Consultoria")
#   pedido = ej.notas.aguardar(r["pedido"]["id"])["pedido"]
#   File.binwrite("nota.pdf", ej.notas.pdf(pedido["nota"]["origem"], pedido["nota"]["id"])) if pedido["estado"] == "autorizada"
module Emissaoja
  # API de produção (padrão do Cliente). Chaves ej_live_.
  BASE_PRODUCAO = "https://emissaoja.com.br"

  # Ambiente de testes: o mesmo emissaoja com um Emissor Nacional simulado (nada vai ao fisco). Chaves ej_test_.
  BASE_SANDBOX = "https://sandbox.emissaoja.com.br"
end

require_relative "emissaoja/version"
require_relative "emissaoja/erro"
require_relative "emissaoja/transporte"
require_relative "emissaoja/recursos/base"
require_relative "emissaoja/recursos/empresa"
require_relative "emissaoja/recursos/tomadores"
require_relative "emissaoja/recursos/servicos"
require_relative "emissaoja/recursos/notas"
require_relative "emissaoja/recursos/emissoes"
require_relative "emissaoja/recursos/operacoes"
require_relative "emissaoja/recursos/cnpj"
require_relative "emissaoja/cliente"
