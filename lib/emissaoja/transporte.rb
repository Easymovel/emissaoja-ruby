# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

module Emissaoja
  # Transporte HTTP padrão: Net::HTTP da biblioteca padrão, uma conexão por chamada e nenhuma repetição
  # automática (emitir e conectar têm efeito; quem decide repetir é quem chama, com a mesma referência).
  #
  # Para testes, ou para usar outro cliente HTTP, passe em Cliente.new(transporte: ...) qualquer objeto que
  # responda a call(metodo, url, cabecalhos, corpo, timeout) e devolva [status, cabecalhos, corpo]:
  # status Integer, cabecalhos Hash (nome => valor) e corpo String com os bytes da resposta.
  class TransporteNetHTTP
    METODOS = {
      "GET" => Net::HTTP::Get,
      "POST" => Net::HTTP::Post,
      "PUT" => Net::HTTP::Put,
      "PATCH" => Net::HTTP::Patch,
      "DELETE" => Net::HTTP::Delete
    }.freeze

    # Viram code "tempo_esgotado". Net::OpenTimeout, Net::ReadTimeout e Net::WriteTimeout herdam de Timeout::Error.
    ERROS_DE_TEMPO = [Timeout::Error, Errno::ETIMEDOUT, (IO::TimeoutError if defined?(IO::TimeoutError))].compact.freeze

    # Viram code "rede": DNS, conexão recusada ou derrubada, TLS, resposta HTTP malformada.
    ERROS_DE_REDE = [
      SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError,
      Net::ProtocolError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError
    ].freeze

    # @param metodo [String] "GET", "POST", "PUT", "PATCH" ou "DELETE"
    # @param url [String] URL completa, com a query já montada
    # @param cabecalhos [Hash{String => String}]
    # @param corpo [String, nil] JSON já serializado, ou nil
    # @param timeout [Numeric] segundos para conectar, para enviar e para cada leitura
    # @return [Array(Integer, Hash{String => String}, String)] status, cabeçalhos (nomes em minúsculas) e corpo em bytes
    # @raise [Erro] code "tempo_esgotado" ou "rede", com status 0
    def call(metodo, url, cabecalhos, corpo, timeout)
      uri = URI.parse(url)
      requisicao = montar_requisicao(metodo, uri, cabecalhos, corpo)
      http = Net::HTTP.new(uri.hostname, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = timeout
      http.read_timeout = timeout
      http.write_timeout = timeout
      http.max_retries = 0 # o Net::HTTP repetiria GET/PUT/DELETE sozinho depois de uma falha de leitura
      resposta = http.start { |conexao| conexao.request(requisicao) }
      [resposta.code.to_i, cabecalhos_de(resposta), resposta.body.to_s.b]
    rescue *ERROS_DE_TEMPO
      raise Erro.new(0, { "code" => "tempo_esgotado", "message" => "A API do emissaoja não respondeu em #{timeout} s." })
    rescue *ERROS_DE_REDE => e
      raise Erro.new(0, { "code" => "rede", "message" => "Falha de rede ao chamar a API do emissaoja: #{e.message}" })
    end

    private

    def montar_requisicao(metodo, uri, cabecalhos, corpo)
      classe = METODOS.fetch(metodo.to_s.upcase) { raise ArgumentError, "método HTTP não suportado: #{metodo}" }
      requisicao = classe.new(uri.request_uri)
      cabecalhos.each { |nome, valor| requisicao[nome] = valor }
      if corpo
        requisicao.body = corpo
      elsif requisicao.request_body_permitted?
        requisicao["Content-Length"] = "0" # POST/PUT sem corpo: o Net::HTTP não mandaria o tamanho
      end
      requisicao
    end

    def cabecalhos_de(resposta)
      cabecalhos = {}
      resposta.each_header { |nome, valor| cabecalhos[nome] = valor }
      cabecalhos
    end
  end
end
