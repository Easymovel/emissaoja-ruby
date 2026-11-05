# frozen_string_literal: true

require_relative "test_helper"

# Cliente, cabeçalhos, chave, erros, query e caminho, com o transporte falso (sem rede).
class ClienteTest < Minitest::Test
  CHAVE = "ej_test_#{"a" * 43}"

  def setup
    @env_original = ENV["EMISSAOJA_KEY"]
    ENV.delete("EMISSAOJA_KEY")
    @t = TransporteFalso.new
    @esperas = []
    @ej = novo_cliente(chave: CHAVE)
  end

  def teardown
    if @env_original.nil?
      ENV.delete("EMISSAOJA_KEY")
    else
      ENV["EMISSAOJA_KEY"] = @env_original
    end
  end

  def novo_cliente(**opcoes)
    Emissaoja::Cliente.new(base_url: "https://emissaoja.test/", transporte: @t, dormir: ->(s) { @esperas << s }, **opcoes)
  end

  def test_status_nao_manda_authorization_nem_precisa_de_chave
    @t.responder("GET", "/v1/status", corpo: { "ok" => true, "motor" => "ok", "ambiente" => "sandbox" })
    ej = novo_cliente # sem chave e sem EMISSAOJA_KEY
    assert_equal "ok", ej.status["motor"]
    chamada = @t.ultima
    assert_equal "https://emissaoja.test/v1/status", chamada.url
    refute chamada.cabecalhos.key?("Authorization")
    assert_equal "application/json", chamada.cabecalhos["Accept"]
    assert_equal "emissaoja-ruby/#{Emissaoja::VERSION}", chamada.cabecalhos["User-Agent"]
  end

  def test_chamada_autenticada_manda_bearer_user_agent_e_timeout
    @t.responder("GET", "/v1/empresa", corpo: { "empresa" => nil })
    assert_equal({ "empresa" => nil }, @ej.empresa.obter)
    chamada = @t.ultima
    assert_equal "GET", chamada.metodo
    assert_equal "Bearer #{CHAVE}", chamada.cabecalhos["Authorization"]
    assert_equal "emissaoja-ruby/#{Emissaoja::VERSION}", chamada.cabecalhos["User-Agent"]
    assert_equal "application/json", chamada.cabecalhos["Accept"]
    refute chamada.cabecalhos.key?("Content-Type")
    assert_nil chamada.corpo
    assert_equal 30, chamada.timeout
  end

  def test_versao_segue_semver
    assert_match(/\A\d+\.\d+\.\d+\z/, Emissaoja::VERSION)
  end

  def test_chave_vem_do_ambiente_na_primeira_chamada
    ej = novo_cliente # construir sem chave e sem EMISSAOJA_KEY não falha
    ENV["EMISSAOJA_KEY"] = "ej_test_do_ambiente"
    @t.responder("GET", "/v1/empresa", corpo: {})
    ej.empresa.obter
    assert_equal "Bearer ej_test_do_ambiente", @t.ultima.cabecalhos["Authorization"]
    assert_equal "ej_test_do_ambiente", ej.chave
  end

  def test_sem_chave_da_erro_local_sem_chamar_a_api
    [novo_cliente, novo_cliente(chave: ""), novo_cliente(chave: "   ")].each do |ej|
      erro = assert_raises(Emissaoja::Erro) { ej.empresa.obter }
      assert_equal "chave_invalida", erro.code
      assert_equal 0, erro.status
      assert_match(/EMISSAOJA_KEY/, erro.message)
    end
    assert_empty @t.chamadas
  end

  def test_erro_422_traz_code_mensagem_bloqueios_extras_e_request_id
    @t.responder("POST", "/v1/notas", status: 422, cabecalhos: { "Content-Type" => "application/json", "X-Request-Id" => "r_422" }, corpo: {
                   "status" => "ERROR", "code" => "nota_bloqueada", "message" => "Antes de emitir, resolva:",
                   "bloqueios" => [{ "code" => "tomador_incompleto", "mensagem" => "Falta o endereço do tomador.", "acao" => "completar_tomador" }]
                 })
    erro = assert_raises(Emissaoja::Erro) do
      @ej.notas.emitir("pedido-0002", tomador_tipo: "pj", tomador_id: "t1", valor: 10)
    end
    assert_kind_of StandardError, erro
    assert_equal 422, erro.status
    assert_equal "nota_bloqueada", erro.code
    assert_equal "Antes de emitir, resolva:", erro.message
    assert_equal "r_422", erro.request_id
    assert_equal ["bloqueios"], erro.extras.keys
    assert_equal "completar_tomador", erro.bloqueios.first["acao"]
  end

  def test_erro_sem_bloqueios_devolve_lista_vazia
    @t.responder("GET", "/v1/emissoes/p0", status: 404, corpo: { "status" => "ERROR", "code" => "pedido_nao_encontrado", "message" => "Pedido não encontrado." })
    erro = assert_raises(Emissaoja::Erro) { @ej.emissoes.obter("p0") }
    assert_equal [404, "pedido_nao_encontrado", "r_teste"], [erro.status, erro.code, erro.request_id]
    assert_equal [], erro.bloqueios
    assert_empty erro.extras
  end

  def test_erro_com_corpo_que_nao_e_json_usa_ate_200_caracteres_do_texto
    html = "<html><body>#{"x" * 300}</body></html>"
    @t.responder("GET", "/v1/empresa", status: 502, corpo: html, cabecalhos: { "content-type" => "text/html" })
    erro = assert_raises(Emissaoja::Erro) { @ej.empresa.obter }
    assert_equal 502, erro.status
    assert_equal "erro_desconhecido", erro.code
    assert_equal html[0, 200], erro.message
    assert_empty erro.extras
    assert_nil erro.request_id
  end

  def test_erro_com_corpo_vazio_vira_http_status
    @t.responder("GET", "/v1/empresa", status: 503, corpo: "", cabecalhos: {})
    erro = assert_raises(Emissaoja::Erro) { @ej.empresa.obter }
    assert_equal [503, "erro_desconhecido", "HTTP 503"], [erro.status, erro.code, erro.message]
  end

  def test_resposta_fora_de_2xx_vira_erro
    @t.responder("GET", "/v1/empresa", status: 302, corpo: "", cabecalhos: { "location" => "https://outro.exemplo" })
    erro = assert_raises(Emissaoja::Erro) { @ej.empresa.obter }
    assert_equal 302, erro.status
    assert_equal "HTTP 302", erro.message
  end

  def test_sucesso_sem_corpo_devolve_hash_vazio
    @t.responder("POST", "/v1/emissoes/p1/conferir", status: 202, corpo: "")
    assert_equal({}, @ej.emissoes.conferir("p1"))
  end

  def test_post_sem_corpo_nao_manda_content_type
    @t.responder("POST", "/v1/empresa/reler-fisco", status: 202, corpo: { "ok" => true })
    @ej.empresa.reler_fisco
    assert_equal "POST", @t.ultima.metodo
    assert_nil @t.ultima.corpo
    refute @t.ultima.cabecalhos.key?("Content-Type")
  end

  def test_query_omite_nulos_e_vazios
    @t.responder("GET", "/v1/tomadores", corpo: { "tomadores" => [], "total" => 0 })
    @ej.tomadores.listar(busca: "", pagina: 2, limite: nil, ordem: "nome")
    assert_equal "pagina=2&ordem=nome", @t.ultima.query
    @ej.tomadores.listar
    assert_equal "https://emissaoja.test/v1/tomadores", @t.ultima.url
    assert_nil @t.ultima.query
  end

  def test_query_codifica_espacos_acentos_e_listas
    @t.responder("GET", "/v1/tomadores/busca", corpo: { "tomadores" => [] })
    @ej.tomadores.buscar("João & Cia")
    assert_equal "q=Jo%C3%A3o+%26+Cia", @t.ultima.query
    @t.responder("GET", "/v1/emissoes", corpo: { "pedidos" => [] })
    @ej.emissoes.listar(estados: %w[na_fila emitindo])
    assert_equal "estados=na_fila%2Cemitindo", @t.ultima.query
    @ej.emissoes.listar(estados: [])
    assert_nil @t.ultima.query
  end

  def test_segmentos_do_caminho_sao_codificados
    @t.responder("GET", "/v1/tomadores/pj/a%20b%2Fc%3F", corpo: { "tomador" => {} })
    @ej.tomadores.obter("pj", "a b/c?")
    assert_equal "https://emissaoja.test/v1/tomadores/pj/a%20b%2Fc%3F", @t.ultima.url
    @t.responder("GET", "/v1/emissoes/a%C3%A7%C3%A3o%2B1~x.y_z-w", corpo: { "pedido" => {} })
    @ej.emissoes.obter("ação+1~x.y_z-w")
    assert_equal "/v1/emissoes/a%C3%A7%C3%A3o%2B1~x.y_z-w", @t.ultima.caminho
  end

  def test_cnpj_consultar_tira_a_pontuacao
    @t.responder("GET", "/v1/cnpj/11222333000181", corpo: { "cnpj" => "11222333000181", "razao_social" => "EMPRESA EXEMPLO LTDA" })
    assert_equal "EMPRESA EXEMPLO LTDA", @ej.cnpj.consultar("11.222.333/0001-81")["razao_social"]
    assert_equal "https://emissaoja.test/v1/cnpj/11222333000181", @t.ultima.url
    @ej.cnpj.consultar(" 11222333000181 ")
    assert_equal "/v1/cnpj/11222333000181", @t.ultima.caminho
  end

  def test_base_url_sem_barra_no_fim_e_padrao_de_producao
    assert_equal "https://emissaoja.test", @ej.base_url
    assert_equal Emissaoja::BASE_PRODUCAO, Emissaoja::Cliente.new(transporte: @t).base_url
    assert_equal "https://sandbox.emissaoja.com.br", Emissaoja::BASE_SANDBOX
  end

  def test_opcoes_invalidas_dao_argument_error
    assert_raises(ArgumentError) { Emissaoja::Cliente.new(base_url: "emissaoja.com.br") }
    assert_raises(ArgumentError) { Emissaoja::Cliente.new(transporte: Object.new) }
    assert_raises(ArgumentError) { Emissaoja::Cliente.new(dormir: Object.new) }
  end

  def test_inspect_nao_mostra_a_chave
    refute_includes @ej.inspect, CHAVE
    refute_includes @ej.notas.inspect, CHAVE
    assert_includes @ej.inspect, "https://emissaoja.test"
  end

  def test_transporte_pode_ser_um_lambda_e_recebe_o_timeout
    recebido = nil
    transporte = lambda do |metodo, url, _cabecalhos, _corpo, timeout|
      recebido = [metodo, url, timeout]
      [200, { "Content-Type" => "application/json" }, '{"ok":true}']
    end
    ej = Emissaoja::Cliente.new(base_url: Emissaoja::BASE_SANDBOX, timeout: 5, transporte: transporte)
    assert_equal({ "ok" => true }, ej.status)
    assert_equal ["GET", "https://sandbox.emissaoja.com.br/v1/status", 5], recebido
  end

  def test_erro_aceita_corpo_com_chaves_symbol
    erro = Emissaoja::Erro.new(409, { code: "sem_empresa", message: "Conecte a empresa.", pedido_id: "p1" }, request_id: "r1")
    assert_equal ["sem_empresa", "Conecte a empresa.", { "pedido_id" => "p1" }, "r1"], [erro.code, erro.message, erro.extras, erro.request_id]
  end
end
