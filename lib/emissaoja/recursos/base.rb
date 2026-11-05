# frozen_string_literal: true

module Emissaoja
  # Os recursos da API, acessados pelo cliente: ej.empresa, ej.tomadores, ej.servicos, ej.notas, ej.emissoes,
  # ej.operacoes e ej.cnpj.
  module Recursos
    # Base comum dos recursos: guarda o cliente e os auxiliares de chamada, de caminho e de espera.
    class Base
      # @param cliente [Cliente]
      def initialize(cliente)
        @cliente = cliente
      end

      private

      def json(metodo, caminho, corpo: nil, query: nil, cabecalhos: nil)
        @cliente.requisitar_json(metodo, caminho, corpo: corpo, query: query, cabecalhos: cabecalhos)
      end

      def bytes(caminho)
        @cliente.requisitar_bytes(caminho)
      end

      # Codifica um segmento do caminho (RFC 3986, mesma regra de ERB::Util.url_encode): letras, números, "-",
      # ".", "_" e "~" passam; o resto vira %XX dos bytes UTF-8. Espaço vira %20 (nunca "+") e "/" vira %2F.
      def segmento(valor)
        valor.to_s.b.gsub(/[^A-Za-z0-9_.~-]/n) { |byte| format("%%%02X", byte.ord) }
      end

      def agora
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def esperar(segundos)
        @cliente.esperar(segundos)
      end

      def tempo_esgotado(mensagem, extras = {})
        Erro.new(0, { "code" => "tempo_esgotado", "message" => mensagem }.merge(extras))
      end
    end
  end
end
