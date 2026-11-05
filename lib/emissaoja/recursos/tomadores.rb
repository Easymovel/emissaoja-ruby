# frozen_string_literal: true

module Emissaoja
  module Recursos
    # Tomadores, os clientes da nota: pessoa jurídica ("pj", pelo CNPJ) ou física ("pf", pelo CPF).
    # Tomador não se apaga: as notas emitidas apontam para ele.
    class Tomadores < Base
      # GET /v1/tomadores: lista paginada.
      # @param busca [String, nil] nome ou documento
      # @param pagina [Integer, nil] a partir de 1
      # @param limite [Integer, nil] até 50
      # @param ordem [String, nil] "nome" ou "recentes"
      # @return [Hash] {"tomadores" => [...], "total" => n, "pagina" => n, "limite" => n}
      def listar(busca: nil, pagina: nil, limite: nil, ordem: nil)
        json("GET", "/v1/tomadores", query: { busca: busca, pagina: pagina, limite: limite, ordem: ordem })
      end

      # GET /v1/tomadores/busca: busca rápida por nome ou documento (2 caracteres ou mais).
      # @param q [String]
      # @return [Hash] {"tomadores" => [...]}
      def buscar(q)
        json("GET", "/v1/tomadores/busca", query: { q: q })
      end

      # POST /v1/tomadores: cria pelo CNPJ (nome e endereço vêm da Receita) ou pelo CPF com o nome.
      # Se o tomador já existia, devolve o mesmo, com "ja_existia" => true.
      # @param documento [String] CNPJ ou CPF
      # @param nome [String, nil] obrigatório para CPF
      # @return [Hash] {"tomador" => {"tipo" => "pj", "id" => ..., "nome" => ..., ...}, "ja_existia" => false}
      def criar(documento, nome: nil)
        corpo = { "documento" => documento.to_s }
        corpo["nome"] = nome unless nome.nil? || nome.to_s.empty?
        json("POST", "/v1/tomadores", corpo: corpo)
      end

      # GET /v1/tomadores/{tipo}/{id}: a ficha do tomador.
      # @param tipo [String] "pj" ou "pf"
      # @param id [String]
      # @return [Hash] {"tomador" => {...}}
      def obter(tipo, id)
        json("GET", "/v1/tomadores/#{segmento(tipo)}/#{segmento(id)}")
      end

      # PUT /v1/tomadores/{tipo}/{id}: edição parcial de endereço e contato (o documento não muda).
      #
      #   ej.tomadores.atualizar("pj", id, email: "financeiro@cliente.com.br", telefone: "3133334444")
      #
      # @param tipo [String] "pj" ou "pf"
      # @param id [String]
      # @param campos [Hash] nome, cep, endereco, numero, complemento, bairro, cidade, estado,
      #   codigo_municipio_ibge, telefone, email, inscricao_municipal (lista completa no OpenAPI)
      # @return [Hash] {"tomador" => {...}}
      def atualizar(tipo, id, campos = {})
        json("PUT", "/v1/tomadores/#{segmento(tipo)}/#{segmento(id)}", corpo: campos)
      end
    end
  end
end
