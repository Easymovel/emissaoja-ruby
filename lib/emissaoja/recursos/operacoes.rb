# frozen_string_literal: true

module Emissaoja
  module Recursos
    # Operações assíncronas; hoje, o cancelamento de nota (ej.notas.cancelar).
    class Operacoes < Base
      # GET /v1/operacoes/{id}: "estado" processando, concluida ou falhou (com "erro").
      # @param id [String]
      # @return [Hash] {"operacao" => {"id" => ..., "tipo" => ..., "estado" => ..., "resultado" => ..., "erro" => ...}}
      def obter(id)
        json("GET", "/v1/operacoes/#{segmento(id)}")
      end

      # Consulta #obter até a operação sair de "processando" (concluida ou falhou).
      # @param id [String]
      # @param intervalo [Numeric] segundos entre as consultas (padrão 2)
      # @param timeout [Numeric] segundos no total (padrão 180)
      # @return [Hash] a última resposta de #obter
      # @raise [Erro] code "tempo_esgotado" (status 0) se não terminar a tempo
      def aguardar(id, intervalo: 2, timeout: 180)
        fim = agora + timeout
        loop do
          resposta = obter(id)
          operacao = resposta["operacao"].is_a?(Hash) ? resposta["operacao"] : {}
          return resposta unless operacao["estado"] == "processando"
          raise tempo_esgotado("A operação não terminou a tempo.") if agora >= fim

          esperar(intervalo)
        end
      end
    end
  end
end
