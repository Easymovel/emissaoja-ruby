# frozen_string_literal: true

module Emissaoja
  module Recursos
    # Consulta de CNPJ nos dados cadastrais da Receita Federal. Não cria tomador: serve para conferir antes de
    # cadastrar (ej.tomadores.criar já preenche pelo CNPJ).
    class Cnpj < Base
      # GET /v1/cnpj/{cnpj}: razão social, situação cadastral, CNAEs, endereço, Simples, MEI e sócios (CPF mascarado).
      # Aceita o CNPJ com ou sem máscara: pontos, barra, hífen e espaços saem antes da chamada.
      # @param cnpj [String]
      # @return [Hash]
      def consultar(cnpj)
        json("GET", "/v1/cnpj/#{segmento(cnpj.to_s.gsub(/[^0-9A-Za-z]/, "").upcase)}")
      end
    end
  end
end
