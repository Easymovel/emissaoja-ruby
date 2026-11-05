# frozen_string_literal: true

module Emissaoja
  module Recursos
    # Serviços da empresa (o que vai na nota: descrição, código de tributação nacional, ISS) e o catálogo
    # nacional de códigos de serviço.
    class Servicos < Base
      # GET /v1/servicos.
      # @param ativos [String, Boolean, nil] "1" (ativos), "0" (inativos) ou "todos"; true vale "1" e false vale "0"
      # @return [Hash] {"servicos" => [...]}
      def listar(ativos: nil)
        ativos = { true => "1", false => "0" }.fetch(ativos, ativos)
        json("GET", "/v1/servicos", query: { ativos: ativos })
      end

      # POST /v1/servicos.
      #
      #   item = ej.servicos.catalogo("consultoria em informática")["itens"].first
      #   ej.servicos.criar(descricao: "Consultoria em TI", c_trib_nac: item["c_trib_nac"],
      #                     trib_issqn: "tributavel", retem_iss: false)
      #
      # @param campos [Hash] descricao, c_trib_nac, trib_issqn ("tributavel" ou "nao_incidencia") e retem_iss
      #   (obrigatórios); nbs, c_trib_mun, tp_oper e aliquota_iss (opcionais)
      # @return [Hash] {"servico" => {...}}
      def criar(campos = {})
        json("POST", "/v1/servicos", corpo: campos)
      end

      # PUT /v1/servicos/{id}: edição parcial. Campo com nil vai como null (limpa o valor).
      # @param id [String]
      # @param campos [Hash]
      # @return [Hash] {"servico" => {...}, "vinculos_atualizados" => n}
      def atualizar(id, campos = {})
        json("PUT", "/v1/servicos/#{segmento(id)}", corpo: campos)
      end

      # DELETE /v1/servicos/{id}: desativa o serviço (o último ativo não pode: 409 ultimo_servico_ativo).
      # As notas emitidas continuam apontando para ele.
      # @param id [String]
      # @return [Hash] {"servico" => {...}}
      def desativar(id)
        json("DELETE", "/v1/servicos/#{segmento(id)}")
      end

      # GET /v1/catalogo/servicos: catálogo nacional de códigos de serviço, por texto.
      # @param q [String] texto da busca
      # @param limite [Integer, nil] até 50
      # @return [Hash] {"itens" => [{"c_trib_nac" => ..., "descricao" => ..., "item_lc116" => ..., "nbs_sugeridos" => [...]}]}
      def catalogo(q, limite: nil)
        json("GET", "/v1/catalogo/servicos", query: { q: q, limite: limite })
      end
    end
  end
end
