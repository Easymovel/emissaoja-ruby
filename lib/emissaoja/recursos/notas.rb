# frozen_string_literal: true

module Emissaoja
  module Recursos
    # Notas: emitir (com idempotência), acompanhar o pedido, listar, baixar PDF e XML e cancelar.
    class Notas < Base
      # Formato da referência (cabeçalho Idempotency-Key): 8 a 64 caracteres, letras, números, _ e -.
      REFERENCIA = /\A[A-Za-z0-9_-]{8,64}\z/

      # Estados em que o pedido de emissão para de mudar.
      ESTADOS_FINAIS = %w[autorizada recusada incerta].freeze

      # POST /v1/notas: prévia + emissão num passo, com o cabeçalho Idempotency-Key = referencia.
      #
      #   r = ej.notas.emitir("pedido-0001", tomador_tipo: "pj", tomador_id: id, valor: 1500, descricao: "Consultoria")
      #   r["pedido"]["id"] # acompanhe com #aguardar
      #
      # A referência é um id seu, único por nota. Repetir a chamada com a mesma referência devolve o mesmo pedido
      # ("repetido" => true) e nunca emite duas vezes; use isso para repetir depois de falha de rede, tempo
      # esgotado ou 503 fila_indisponivel. A referência é conferida aqui, antes de qualquer chamada à API.
      #
      # @param referencia [String] 8 a 64 caracteres: letras, números, _ e -
      # @param tomador_tipo [String] "pj" ou "pf"
      # @param tomador_id [String] id do tomador
      # @param valor [Numeric] em reais, até 2 casas (Integer, Float ou BigDecimal)
      # @param campos [Hash] opcionais: servico_id (omitido: o serviço principal), descricao (até 2000 caracteres),
      #   competencia ("AAAA-MM-DD"; omitida: hoje), retem_iss, aliquota_iss, municipio_prestacao (código IBGE),
      #   confirmo_repeticao, permitir_repetida_de. Os nil não vão no corpo.
      # @return [Hash] {"pedido" => {...}, "previa" => {...}} (202) ou {"pedido" => {...}, "repetido" => true} (200)
      # @raise [Erro] chave_idempotencia_invalida (status 0, sem chamar a API), nota_bloqueada (422, veja
      #   Erro#bloqueios), possivel_duplicada, emissao_repetida_recente, limite_notas...
      def emitir(referencia, tomador_tipo:, tomador_id:, valor:, **campos)
        chave = referencia.to_s
        unless REFERENCIA.match?(chave)
          raise Erro.new(0, { "code" => "chave_idempotencia_invalida",
                              "message" => "Informe a referência da nota: 8 a 64 caracteres (letras, números, _ e -), única por nota." })
        end

        corpo = { "tomador_tipo" => tomador_tipo, "tomador_id" => tomador_id, "valor" => valor }
        campos.each { |nome, item| corpo[nome.to_s] = item unless item.nil? }
        json("POST", "/v1/notas", corpo: corpo, cabecalhos: { "Idempotency-Key" => chave })
      end

      # Consulta o pedido (GET /v1/emissoes/{id}) até "autorizada", "recusada" ou "incerta". Entre as consultas,
      # espera o que a API pede em "proxima_consulta_ms" (3 s quando ela não diz), nunca menos que intervalo_minimo.
      #
      # @param pedido_id [String] o "id" do pedido devolvido por #emitir
      # @param timeout [Numeric] segundos no total (padrão 180)
      # @param intervalo_minimo [Numeric] segundos (padrão 1)
      # @return [Hash] {"pedido" => {"estado" => "autorizada", "numero" => ..., "chave_acesso" => ...,
      #   "nota" => {"origem" => "local", "id" => ...}, ...}}
      # @raise [Erro] code "tempo_esgotado" (status 0, extras["pedido_id"]) se não terminar a tempo; o pedido
      #   continua andando e pode ser consultado depois com ej.emissoes.obter
      def aguardar(pedido_id, timeout: 180, intervalo_minimo: 1)
        fim = agora + timeout
        loop do
          resposta = @cliente.emissoes.obter(pedido_id)
          pedido = resposta["pedido"].is_a?(Hash) ? resposta["pedido"] : {}
          return resposta if ESTADOS_FINAIS.include?(pedido["estado"])
          if agora >= fim
            raise tempo_esgotado("O pedido não terminou a tempo; consulte de novo mais tarde.", { "pedido_id" => pedido_id })
          end

          esperar([intervalo_minimo, proxima_consulta(pedido)].max)
        end
      end

      # GET /v1/notas: notas locais e importadas, paginadas por cursor.
      # @param periodo [String, nil] "mes_atual", "mes_anterior", "ano_atual", "12_meses" (padrão da API) ou
      #   "personalizado" (com de e ate)
      # @param de [String, Date, nil] AAAA-MM-DD
      # @param ate [String, Date, nil] AAAA-MM-DD
      # @param situacao [String, nil] "todas" (padrão da API), "emitidas" ou "canceladas"
      # @param busca [String, nil] número da nota, CPF/CNPJ ou nome do tomador
      # @param cursor [String, nil] o "proximo_cursor" da página anterior
      # @param limite [Integer, nil] até 50
      # @return [Hash] {"notas" => [...], "total" => n, "janela_cheia" => false, "proximo_cursor" => ... ou nil}
      def listar(periodo: nil, de: nil, ate: nil, situacao: nil, busca: nil, cursor: nil, limite: nil)
        json("GET", "/v1/notas", query: { periodo: periodo, de: de, ate: ate, situacao: situacao, busca: busca,
                                          cursor: cursor, limite: limite })
      end

      # GET /v1/notas/{origem}/{id}/pdf: o DANFSe em PDF.
      #
      #   File.binwrite("nota.pdf", ej.notas.pdf(nota["origem"], nota["id"]))
      #
      # @param origem [String] "local" (emitida pelo emissaoja) ou "importada"
      # @param id [String]
      # @return [String] bytes do PDF (encoding ASCII-8BIT)
      def pdf(origem, id)
        bytes("/v1/notas/#{segmento(origem)}/#{segmento(id)}/pdf")
      end

      # GET /v1/notas/{origem}/{id}/xml: o XML da NFS-e.
      # @param origem [String] "local" ou "importada"
      # @param id [String]
      # @return [String] texto em UTF-8
      def xml(origem, id)
        bytes("/v1/notas/#{segmento(origem)}/#{segmento(id)}/xml").force_encoding(Encoding::UTF_8)
      end

      # POST /v1/notas/{origem}/{id}/cancelar: pede o cancelamento no Emissor Nacional. Responde 202 com a
      # "operacao"; acompanhe com ej.operacoes.aguardar(operacao["id"]).
      # @param origem [String] "local" ou "importada"
      # @param id [String]
      # @param motivo [String, Integer] "1" (erro na emissão) ou "2" (serviço não prestado)
      # @param justificativa [String, nil] de 15 a 255 caracteres
      # @return [Hash] {"operacao" => {"id" => ..., "estado" => "processando", ...}}
      def cancelar(origem, id, motivo:, justificativa: nil)
        corpo = { "motivo" => motivo.to_s }
        corpo["justificativa"] = justificativa unless justificativa.nil? || justificativa.to_s.empty?
        json("POST", "/v1/notas/#{segmento(origem)}/#{segmento(id)}/cancelar", corpo: corpo)
      end

      private

      # Segundos até a próxima consulta: proxima_consulta_ms da API, ou 3 s quando ela não diz.
      def proxima_consulta(pedido)
        ms = pedido["proxima_consulta_ms"]
        ms = 3000 unless ms.is_a?(Numeric) && ms.positive?
        ms / 1000.0
      end
    end
  end
end
