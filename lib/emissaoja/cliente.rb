# frozen_string_literal: true

require "json"
require "uri"

module Emissaoja
  # Cliente da API do emissaoja (https://emissaoja.com.br/docs/).
  #
  #   ej = Emissaoja::Cliente.new(chave: ENV["EMISSAOJA_KEY"], base_url: Emissaoja::BASE_SANDBOX)
  #   r = ej.notas.emitir("pedido-0001", tomador_tipo: "pj", tomador_id: id, valor: 1500, descricao: "Consultoria")
  #   ej.notas.aguardar(r["pedido"]["id"])
  #
  # Recursos: empresa, tomadores, servicos, notas, emissoes, operacoes e cnpj. As respostas são Hash com chaves
  # String (o JSON da API, em snake_case) e os erros viram Emissaoja::Erro. O cliente não guarda conexão aberta
  # nem estado além da chave: uma instância pode ser compartilhada entre threads (Puma, Sidekiq).
  class Cliente
    # @return [String] URL base da API, sem barra no fim
    attr_reader :base_url

    # @return [Numeric] segundos para conectar, para enviar e para cada leitura
    attr_reader :timeout

    # @return [Recursos::Empresa] conexão com o Emissor Nacional e configuração fiscal
    attr_reader :empresa

    # @return [Recursos::Tomadores] clientes da nota (pj e pf)
    attr_reader :tomadores

    # @return [Recursos::Servicos] serviços da empresa e catálogo nacional
    attr_reader :servicos

    # @return [Recursos::Notas] emitir, aguardar, listar, PDF, XML e cancelar
    attr_reader :notas

    # @return [Recursos::Emissoes] pedidos de emissão
    attr_reader :emissoes

    # @return [Recursos::Operacoes] operações assíncronas (cancelamento)
    attr_reader :operacoes

    # @return [Recursos::Cnpj] consulta de CNPJ
    attr_reader :cnpj

    # @param chave [String, nil] chave da API (ej_live_ em produção, ej_test_ no sandbox). Sem ela, o cliente lê
    #   a variável de ambiente EMISSAOJA_KEY na primeira chamada que precisa da chave (não aqui no construtor).
    # @param base_url [String, nil] BASE_PRODUCAO (padrão) ou BASE_SANDBOX
    # @param timeout [Numeric, nil] segundos (padrão 30)
    # @param transporte [#call, nil] objeto com call(metodo, url, cabecalhos, corpo, timeout) que devolve
    #   [status, cabecalhos, corpo]; padrão TransporteNetHTTP. Útil nos testes.
    # @param dormir [#call, nil] objeto com call(segundos), usado entre as consultas dos métodos aguardar;
    #   padrão Kernel.sleep. Nos testes, um lambda que não dorme.
    def initialize(chave: nil, base_url: BASE_PRODUCAO, timeout: 30, transporte: nil, dormir: nil)
      @chave = chave
      @base_url = (base_url || BASE_PRODUCAO).to_s.sub(%r{/+\z}, "")
      @timeout = timeout || 30
      @transporte = transporte || TransporteNetHTTP.new
      @dormir = dormir || ->(segundos) { Kernel.sleep(segundos) }
      unless %r{\Ahttps?://[^/]}i.match?(@base_url)
        raise ArgumentError, "base_url precisa começar com https:// (ou http://): #{@base_url.inspect}"
      end
      raise ArgumentError, "transporte precisa responder a call(metodo, url, cabecalhos, corpo, timeout)" unless @transporte.respond_to?(:call)
      raise ArgumentError, "dormir precisa responder a call(segundos)" unless @dormir.respond_to?(:call)

      @empresa = Recursos::Empresa.new(self)
      @tomadores = Recursos::Tomadores.new(self)
      @servicos = Recursos::Servicos.new(self)
      @notas = Recursos::Notas.new(self)
      @emissoes = Recursos::Emissoes.new(self)
      @operacoes = Recursos::Operacoes.new(self)
      @cnpj = Recursos::Cnpj.new(self)
    end

    # A chave em uso. Sem chave no construtor, lê EMISSAOJA_KEY agora (na primeira chamada que precisa dela).
    # @return [String]
    # @raise [Erro] code "chave_invalida" (status 0) sem chave e sem EMISSAOJA_KEY; nada é enviado à API
    def chave
      @chave = texto_ou_nil(@chave) || texto_ou_nil(ENV["EMISSAOJA_KEY"])
      return @chave if @chave

      raise Erro.new(0, { "code" => "chave_invalida",
                          "message" => "Informe a chave: Emissaoja::Cliente.new(chave: ...) ou a variável de ambiente EMISSAOJA_KEY." })
    end

    # GET /v1/status: versão, estado do motor e ambiente ("producao" ou "sandbox"). Não usa a chave.
    # @return [Hash] {"ok" => true, "versao" => "...", "motor" => "ok", "ambiente" => "producao", "tempo" => "..."}
    def status
      requisitar_json("GET", "/v1/status", sem_chave: true)
    end

    # Não mostra a chave: inspect aparece em logs, no console e em mensagens de erro.
    def inspect
      "#<#{self.class.name} base_url=#{@base_url.inspect}>"
    end

    # Chamada que responde JSON. Uso interno dos recursos.
    # @api private
    # @return [Hash] o corpo da resposta ({} quando vazio ou quando não é um objeto JSON)
    # @raise [Erro] resposta fora de 2xx, falha de rede ou tempo esgotado
    def requisitar_json(metodo, caminho, corpo: nil, query: nil, cabecalhos: nil, sem_chave: false)
      status, cabecalhos_resposta, bruto = requisitar(metodo, caminho, corpo: corpo, query: query,
                                                                       cabecalhos: cabecalhos, sem_chave: sem_chave)
      texto = texto_utf8(bruto)
      dados = ler_json(texto)
      raise erro_http(status, cabecalhos_resposta, texto, dados) unless sucesso?(status)

      dados.is_a?(Hash) ? dados : {}
    end

    # GET que responde bytes (PDF, XML). Uso interno dos recursos.
    # @api private
    # @return [String] o corpo, em ASCII-8BIT
    # @raise [Erro] resposta fora de 2xx, falha de rede ou tempo esgotado
    def requisitar_bytes(caminho)
      status, cabecalhos_resposta, bruto = requisitar("GET", caminho)
      unless sucesso?(status)
        texto = texto_utf8(bruto)
        raise erro_http(status, cabecalhos_resposta, texto, ler_json(texto))
      end
      bruto.b
    end

    # Espera entre as consultas dos métodos aguardar. Uso interno dos recursos.
    # @api private
    def esperar(segundos)
      @dormir.call(segundos)
    end

    private

    def requisitar(metodo, caminho, corpo: nil, query: nil, cabecalhos: nil, sem_chave: false)
      h = { "Accept" => "application/json", "User-Agent" => "emissaoja-ruby/#{VERSION}" }
      h.merge!(cabecalhos) if cabecalhos
      h["Authorization"] = "Bearer #{chave}" unless sem_chave
      corpo_json = nil
      unless corpo.nil?
        h["Content-Type"] = "application/json"
        corpo_json = JSON.generate(para_json(corpo))
      end
      status, cabecalhos_resposta, bruto = @transporte.call(metodo, montar_url(caminho, query), h, corpo_json, @timeout)
      [Integer(status), normalizar_cabecalhos(cabecalhos_resposta), bruto.to_s]
    end

    def montar_url(caminho, query)
      url = @base_url + caminho
      pares = pares_da_query(query)
      pares.empty? ? url : "#{url}?#{URI.encode_www_form(pares)}"
    end

    # Omite nil e vazios. Lista vira texto separado por vírgula (ex.: estados: %w[na_fila emitindo]).
    def pares_da_query(query)
      (query || {}).each_with_object([]) do |(nome, valor), pares|
        valor = valor.join(",") if valor.is_a?(Array)
        next if valor.nil? || valor.to_s.empty?

        pares << [nome.to_s, valor.to_s]
      end
    end

    # Chaves viram String; BigDecimal e Rational viram Float (sem isso o JSON levaria texto, como "0.15e4").
    def para_json(valor)
      case valor
      when Hash then valor.each_with_object({}) { |(nome, item), h| h[nome.to_s] = para_json(item) }
      when Array then valor.map { |item| para_json(item) }
      when Integer, Float then valor
      when Numeric then valor.to_f
      else valor
      end
    end

    def normalizar_cabecalhos(cabecalhos)
      (cabecalhos || {}).each_with_object({}) do |(nome, valor), h|
        h[nome.to_s.downcase] = valor.is_a?(Array) ? valor.join(", ") : valor
      end
    end

    def texto_utf8(bruto)
      String.new(bruto, encoding: Encoding::UTF_8).scrub
    end

    def ler_json(texto)
      return nil if texto.strip.empty?

      JSON.parse(texto)
    rescue JSON::ParserError
      nil
    end

    def erro_http(status, cabecalhos, texto, dados)
      corpo = dados.is_a?(Hash) ? dados : { "message" => resumo(texto, status) }
      Erro.new(status, corpo, request_id: cabecalhos["x-request-id"])
    end

    # Corpo que não é JSON (página de proxy, por exemplo): até 200 caracteres do texto.
    def resumo(texto, status)
      limpo = texto.strip
      limpo.empty? ? "HTTP #{status}" : limpo[0, 200]
    end

    def sucesso?(status)
      status >= 200 && status <= 299
    end

    def texto_ou_nil(valor)
      texto = valor.to_s.strip
      texto.empty? ? nil : texto
    end
  end
end
