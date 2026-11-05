# frozen_string_literal: true

module Emissaoja
  # Erro da API do emissaoja ou do próprio cliente (rede, tempo esgotado, chave ausente, referência inválida).
  #
  # Decida pelo +code+ (a lista fechada da API, em snake_case), nunca pelo texto da mensagem:
  #
  #   begin
  #     ej.notas.emitir("pedido-0001", tomador_tipo: "pj", tomador_id: id, valor: 1500)
  #   rescue Emissaoja::Erro => e
  #     e.status      # 422 (HTTP; 0 quando o erro é local, de rede ou de tempo)
  #     e.code        # "nota_bloqueada"
  #     e.message     # "Antes de emitir, resolva:"
  #     e.bloqueios   # [{"code" => "tomador_incompleto", "mensagem" => "...", "acao" => "completar_tomador"}]
  #     e.extras      # os demais campos do corpo: bloqueios, nota_igual_recente, pedido_id, retry_after...
  #     e.request_id  # cabeçalho x-request-id da resposta, para falar com o suporte
  #   end
  class Erro < StandardError
    # @return [Integer] status HTTP; 0 para erro local, falha de rede ou tempo esgotado
    attr_reader :status

    # @return [String] código da lista fechada da API (ex.: "chave_invalida", "nota_bloqueada", "limite_notas");
    #   "erro_desconhecido" quando a resposta não traz um
    attr_reader :code

    # @return [Hash{String => Object}] os outros campos do corpo do erro (tudo menos status, code e message)
    attr_reader :extras

    # @return [String, nil] valor do cabeçalho x-request-id da resposta
    attr_reader :request_id

    # @param status [Integer] status HTTP (0 para erro local, de rede ou de tempo)
    # @param corpo [Hash, nil] corpo do erro, como {"code" => ..., "message" => ...}; chaves String ou Symbol
    # @param request_id [String, nil] cabeçalho x-request-id
    def initialize(status, corpo = nil, request_id: nil)
      dados = corpo.is_a?(Hash) ? corpo.transform_keys(&:to_s) : {}
      mensagem = dados["message"].to_s
      super(mensagem.empty? ? "HTTP #{status}" : mensagem)
      @status = status.to_i
      codigo = dados["code"].to_s
      @code = codigo.empty? ? "erro_desconhecido" : codigo
      @extras = dados.reject { |campo, _| %w[status message code].include?(campo) }
      @request_id = request_id
    end

    # Os bloqueios de um 422 nota_bloqueada, cada um com "code", "mensagem" e "acao" (o que falta no cadastro).
    # Vazio nos outros erros.
    # @return [Array<Hash{String => String}>]
    def bloqueios
      lista = extras["bloqueios"]
      lista.is_a?(Array) ? lista : []
    end
  end
end
