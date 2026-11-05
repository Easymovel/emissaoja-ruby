# frozen_string_literal: true

require_relative "test_helper"
require_relative "servidor_local"

# O transporte Net::HTTP de verdade contra um servidor HTTP em 127.0.0.1 (nada sai da máquina).
class TransporteTest < Minitest::Test
  def teardown
    @servidor&.fechar
  end

  def servidor(&responder)
    @servidor = ServidorLocal.new(&responder)
  end

  def cliente(timeout: 5)
    Emissaoja::Cliente.new(chave: "ej_test_local", base_url: @servidor.url, timeout: timeout)
  end

  def test_envia_metodo_alvo_cabecalhos_e_corpo_e_devolve_status_cabecalhos_e_bytes
    servidor { [201, { "Content-Type" => "application/json", "X-Request-Id" => "r_local" }, '{"tomador":{"id":"t1"}}'] }
    status, cabecalhos, corpo = Emissaoja::TransporteNetHTTP.new.call(
      "POST", "#{@servidor.url}/v1/tomadores?x=1",
      { "Authorization" => "Bearer k", "Content-Type" => "application/json", "Idempotency-Key" => "pedido-0001" },
      '{"documento":"12345678000195"}', 5
    )
    assert_equal 201, status
    assert_equal "r_local", cabecalhos["x-request-id"]
    assert_equal '{"tomador":{"id":"t1"}}', corpo
    assert_equal Encoding::ASCII_8BIT, corpo.encoding

    requisicao = @servidor.requisicoes.first
    assert_equal "POST", requisicao.metodo
    assert_equal "/v1/tomadores?x=1", requisicao.alvo
    assert_equal "Bearer k", requisicao.cabecalhos["authorization"]
    assert_equal "pedido-0001", requisicao.cabecalhos["idempotency-key"]
    assert_equal "application/json", requisicao.cabecalhos["content-type"]
    assert_equal '{"documento":"12345678000195"}', requisicao.corpo
  end

  def test_cliente_inteiro_por_http_pdf_em_bytes_e_erro_com_request_id
    pdf = "%PDF-1.4\n\xE2\xE3\xCF\xD3\n%%EOF".b
    servidor do |requisicao|
      if requisicao.alvo.end_with?("/pdf")
        [200, { "Content-Type" => "application/pdf" }, pdf]
      else
        [422, { "Content-Type" => "application/json", "X-Request-Id" => "r_http" },
         '{"status":"ERROR","code":"nota_bloqueada","message":"Antes de emitir, resolva:","bloqueios":[]}']
      end
    end
    ej = cliente
    assert_equal pdf, ej.notas.pdf("local", "a b")
    assert_equal "/v1/notas/local/a%20b/pdf", @servidor.requisicoes.last.alvo
    assert_equal "emissaoja-ruby/#{Emissaoja::VERSION}", @servidor.requisicoes.last.cabecalhos["user-agent"]
    assert_equal "Bearer ej_test_local", @servidor.requisicoes.last.cabecalhos["authorization"]

    erro = assert_raises(Emissaoja::Erro) do
      ej.notas.emitir("pedido-0001", tomador_tipo: "pj", tomador_id: "t1", valor: 10)
    end
    assert_equal [422, "nota_bloqueada", "r_http"], [erro.status, erro.code, erro.request_id]
    assert_equal "pedido-0001", @servidor.requisicoes.last.cabecalhos["idempotency-key"]
    assert_equal({ "tomador_tipo" => "pj", "tomador_id" => "t1", "valor" => 10 }, JSON.parse(@servidor.requisicoes.last.corpo))
  end

  def test_post_sem_corpo_manda_content_length_zero_e_nenhum_content_type
    servidor { [202, { "Content-Type" => "application/json" }, "{}"] }
    assert_equal({}, cliente.empresa.reler_fisco)
    requisicao = @servidor.requisicoes.first
    assert_equal "POST", requisicao.metodo
    assert_equal "0", requisicao.cabecalhos["content-length"]
    refute requisicao.cabecalhos.key?("content-type")
  end

  def test_api_que_nao_responde_vira_tempo_esgotado_sem_repetir
    servidor { nil } # segura a conexão sem responder
    erro = assert_raises(Emissaoja::Erro) { cliente(timeout: 0.3).empresa.obter }
    assert_equal "tempo_esgotado", erro.code
    assert_equal 0, erro.status
    assert_equal 1, @servidor.requisicoes.size # o Net::HTTP não repetiu o GET sozinho
  end

  def test_conexao_recusada_vira_erro_de_rede
    livre = TCPServer.new("127.0.0.1", 0)
    porta = livre.addr[1]
    livre.close # a porta fica sem ninguém escutando
    ej = Emissaoja::Cliente.new(chave: "ej_test_local", base_url: "http://127.0.0.1:#{porta}", timeout: 2)
    erro = assert_raises(Emissaoja::Erro) { ej.empresa.obter }
    assert_equal "rede", erro.code
    assert_equal 0, erro.status
  end
end
