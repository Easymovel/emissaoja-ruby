# frozen_string_literal: true

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "json"
require "uri"
require "minitest/autorun"
require "emissaoja"

# Transporte falso: guarda as chamadas e responde pelo método e pelo caminho, sem rede.
class TransporteFalso
  # Uma chamada recebida, com atalhos para o caminho, a query e o corpo JSON.
  Chamada = Struct.new(:metodo, :url, :cabecalhos, :corpo, :timeout) do
    def caminho
      URI.parse(url).path
    end

    def query
      URI.parse(url).query
    end

    def json
      JSON.parse(corpo)
    end
  end

  NAO_ENCONTRADA = JSON.generate({ "status" => "ERROR", "code" => "not_found", "message" => "Rota não encontrada." })

  attr_reader :chamadas

  def initialize
    @chamadas = []
    @respostas = Hash.new { |hash, rota| hash[rota] = [] }
  end

  # Programa a resposta de METODO + caminho (o caminho como vai na URL, já codificado).
  # corpo Hash/Array vira JSON; String vai crua (PDF, HTML). Várias respostas para a mesma rota saem em
  # ordem, e a última se repete.
  def responder(metodo, caminho, status: 200, corpo: {}, cabecalhos: { "content-type" => "application/json", "x-request-id" => "r_teste" })
    @respostas["#{metodo} #{caminho}"] << [status, cabecalhos, corpo]
    self
  end

  def call(metodo, url, cabecalhos, corpo, timeout)
    chamada = Chamada.new(metodo, url, cabecalhos, corpo, timeout)
    @chamadas << chamada
    fila = @respostas["#{metodo} #{chamada.caminho}"]
    return [404, { "content-type" => "application/json" }, NAO_ENCONTRADA] if fila.empty?

    status, cabecalhos_resposta, dados = fila.length > 1 ? fila.shift : fila.first
    [status, cabecalhos_resposta, dados.is_a?(String) ? dados : JSON.generate(dados)]
  end

  def ultima
    @chamadas.last
  end
end
