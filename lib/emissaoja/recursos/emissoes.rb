# frozen_string_literal: true

module Emissaoja
  module Recursos
    # Pedidos de emissão (o que ej.notas.emitir devolve): acompanhar, listar e conferir.
    class Emissoes < Base
      # GET /v1/emissoes/{id}: o pedido, com "estado" (na_fila, emitindo, confirmando, autorizada, recusada ou
      # incerta) e "proxima_consulta_ms" (quando consultar de novo).
      # @param id [String]
      # @return [Hash] {"pedido" => {...}}
      def obter(id)
        json("GET", "/v1/emissoes/#{segmento(id)}")
      end

      # GET /v1/emissoes: pedidos em andamento, ou nos estados pedidos.
      # @param estados [String, Array<String>, nil] "na_fila,emitindo" ou %w[na_fila emitindo]
      # @return [Hash] {"pedidos" => [...]}
      def listar(estados: nil)
        json("GET", "/v1/emissoes", query: { estados: estados })
      end

      # POST /v1/emissoes/{id}/conferir: confere no Emissor Nacional um pedido "incerta" (se a nota saiu ou não).
      # @param id [String]
      # @return [Hash] {"pedido" => {...}}
      def conferir(id)
        json("POST", "/v1/emissoes/#{segmento(id)}/conferir")
      end
    end
  end
end
