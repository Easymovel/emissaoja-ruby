# frozen_string_literal: true

require_relative "test_helper"

# Recursos (empresa, tomadores, servicos, notas, emissoes, operacoes) com o transporte falso: rotas, corpos,
# idempotência e os métodos aguardar, sem rede e sem dormir.
class RecursosTest < Minitest::Test
  def setup
    @t = TransporteFalso.new
    @esperas = []
    @ej = Emissaoja::Cliente.new(chave: "ej_test_chave", base_url: "https://emissaoja.test", transporte: @t,
                                 dormir: ->(segundos) { @esperas << segundos })
  end

  def pedido(estado, extras = {})
    { "pedido" => { "id" => "p1", "estado" => estado }.merge(extras) }
  end

  # ---- notas.emitir ----

  def test_emitir_valida_a_referencia_antes_de_chamar_a_api
    [nil, "", "curta", "tem espaco 123", "acentuação-0001", "pedido/0001", "a" * 65, "pedido-0001\n"].each do |referencia|
      erro = assert_raises(Emissaoja::Erro, referencia.inspect) do
        @ej.notas.emitir(referencia, tomador_tipo: "pj", tomador_id: "t1", valor: 10)
      end
      assert_equal "chave_idempotencia_invalida", erro.code
      assert_equal 0, erro.status
    end
    assert_empty @t.chamadas
  end

  def test_emitir_manda_idempotency_key_e_tira_os_campos_nulos
    @t.responder("POST", "/v1/notas", status: 202, corpo: pedido("na_fila").merge("previa" => { "avisos" => [] }))
    r = @ej.notas.emitir("pedido-0001", tomador_tipo: "pj", tomador_id: "t1", valor: 1500,
                                        descricao: "Consultoria de novembro", competencia: nil, servico_id: nil, retem_iss: false)
    assert_equal "p1", r["pedido"]["id"]
    chamada = @t.ultima
    assert_equal "POST", chamada.metodo
    assert_equal "pedido-0001", chamada.cabecalhos["Idempotency-Key"]
    assert_equal "application/json", chamada.cabecalhos["Content-Type"]
    assert_equal({ "tomador_tipo" => "pj", "tomador_id" => "t1", "valor" => 1500,
                   "descricao" => "Consultoria de novembro", "retem_iss" => false }, chamada.json)
  end

  def test_emitir_aceita_referencia_de_8_e_de_64_caracteres
    @t.responder("POST", "/v1/notas", status: 202, corpo: pedido("na_fila"))
    @ej.notas.emitir("a" * 8, tomador_tipo: "pf", tomador_id: "t2", valor: 1)
    @ej.notas.emitir("Z9_-" * 16, tomador_tipo: "pf", tomador_id: "t2", valor: 1)
    assert_equal ["a" * 8, "Z9_-" * 16], @t.chamadas.map { |c| c.cabecalhos["Idempotency-Key"] }
  end

  def test_emitir_repetido_devolve_o_mesmo_pedido
    @t.responder("POST", "/v1/notas", status: 200, corpo: pedido("autorizada").merge("repetido" => true))
    r = @ej.notas.emitir("pedido-0001", tomador_tipo: "pj", tomador_id: "t1", valor: 1500)
    assert_equal [true, "p1"], [r["repetido"], r["pedido"]["id"]]
  end

  def test_valor_racional_ou_decimal_vai_como_numero_no_json
    @t.responder("POST", "/v1/notas", status: 202, corpo: pedido("na_fila"))
    @ej.notas.emitir("pedido-0003", tomador_tipo: "pj", tomador_id: "t1", valor: Rational(3001, 2))
    assert_includes @t.ultima.corpo, '"valor":1500.5'
    assert_equal 1500.5, @t.ultima.json["valor"]
  end

  # ---- notas.aguardar e os outros aguardar ----

  def test_aguardar_respeita_proxima_consulta_ms
    @t.responder("GET", "/v1/emissoes/p1", corpo: pedido("na_fila", "proxima_consulta_ms" => 1500))
    @t.responder("GET", "/v1/emissoes/p1", corpo: pedido("emitindo", "proxima_consulta_ms" => 5))
    @t.responder("GET", "/v1/emissoes/p1", corpo: pedido("confirmando", "proxima_consulta_ms" => nil))
    @t.responder("GET", "/v1/emissoes/p1", corpo: pedido("autorizada", "numero" => "42", "nota" => { "origem" => "local", "id" => "n1" }))
    r = @ej.notas.aguardar("p1", intervalo_minimo: 0.01)
    assert_equal "autorizada", r["pedido"]["estado"]
    assert_equal "42", r["pedido"]["numero"]
    # 1500 ms; 5 ms sobe para o intervalo mínimo (0,01 s); sem proxima_consulta_ms, 3 s
    assert_equal [1.5, 0.01, 3.0], @esperas
    assert_equal 4, @t.chamadas.size
  end

  def test_aguardar_para_em_recusada_e_em_incerta
    %w[recusada incerta].each do |estado|
      @t.responder("GET", "/v1/emissoes/#{estado}", corpo: { "pedido" => { "id" => estado, "estado" => estado } })
      assert_equal estado, @ej.notas.aguardar(estado)["pedido"]["estado"]
    end
    assert_empty @esperas
  end

  def test_aguardar_estoura_tempo_esgotado_com_o_pedido_id
    @t.responder("GET", "/v1/emissoes/p9", corpo: pedido("emitindo", "id" => "p9", "proxima_consulta_ms" => 1))
    erro = assert_raises(Emissaoja::Erro) { @ej.notas.aguardar("p9", timeout: 0) }
    assert_equal "tempo_esgotado", erro.code
    assert_equal 0, erro.status
    assert_equal "p9", erro.extras["pedido_id"]
    assert_empty @esperas
  end

  def test_aguardar_credencial_ate_sair_de_aguardar
    @t.responder("GET", "/v1/empresa/credencial", corpo: { "tentativa" => { "proximo_passo" => "aguardar" } })
    @t.responder("GET", "/v1/empresa/credencial", corpo: { "tentativa" => { "proximo_passo" => "configurando" } })
    r = @ej.empresa.aguardar_credencial(intervalo: 0.5)
    assert_equal "configurando", r["tentativa"]["proximo_passo"]
    assert_equal [0.5], @esperas
  end

  def test_aguardar_credencial_sem_tentativa_volta_na_hora
    @t.responder("GET", "/v1/empresa/credencial", corpo: { "credencial" => { "estado" => "ausente" }, "tentativa" => nil })
    assert_nil @ej.empresa.aguardar_credencial["tentativa"]
    assert_empty @esperas
  end

  def test_aguardar_credencial_estoura_tempo_esgotado
    @t.responder("GET", "/v1/empresa/credencial", corpo: { "tentativa" => { "proximo_passo" => "aguardar" } })
    erro = assert_raises(Emissaoja::Erro) { @ej.empresa.aguardar_credencial(timeout: 0) }
    assert_equal "tempo_esgotado", erro.code
  end

  def test_operacoes_aguardar_ate_sair_de_processando
    @t.responder("GET", "/v1/operacoes/o1", corpo: { "operacao" => { "id" => "o1", "estado" => "processando" } })
    @t.responder("GET", "/v1/operacoes/o1", corpo: { "operacao" => { "id" => "o1", "estado" => "concluida" } })
    r = @ej.operacoes.aguardar("o1", intervalo: 0.25)
    assert_equal "concluida", r["operacao"]["estado"]
    assert_equal [0.25], @esperas
  end

  # ---- PDF e XML ----

  def test_pdf_devolve_bytes_e_xml_devolve_texto_utf8
    pdf = "%PDF-1.4\n\xE2\xE3\xCF\xD3\n%%EOF".b
    @t.responder("GET", "/v1/notas/local/n1/pdf", corpo: pdf, cabecalhos: { "content-type" => "application/pdf" })
    bytes = @ej.notas.pdf("local", "n1")
    assert_equal Encoding::ASCII_8BIT, bytes.encoding
    assert_equal pdf, bytes

    xml = "<NFSe><infNFSe><xLocEmi>São José</xLocEmi></infNFSe></NFSe>"
    @t.responder("GET", "/v1/notas/importada/n2/xml", corpo: xml.b, cabecalhos: { "content-type" => "application/xml" })
    texto = @ej.notas.xml("importada", "n2")
    assert_equal Encoding::UTF_8, texto.encoding
    assert_equal xml, texto
  end

  def test_pdf_de_nota_que_nao_existe_vira_erro
    @t.responder("GET", "/v1/notas/local/n0/pdf", status: 404,
                                                   corpo: { "status" => "ERROR", "code" => "nota_nao_encontrada", "message" => "Nota não encontrada." })
    erro = assert_raises(Emissaoja::Erro) { @ej.notas.pdf("local", "n0") }
    assert_equal [404, "nota_nao_encontrada", "Nota não encontrada.", "r_teste"], [erro.status, erro.code, erro.message, erro.request_id]
  end

  # ---- corpos e rotas dos outros recursos ----

  def test_empresa_conectar_fiscal_e_onboarding
    @t.responder("PUT", "/v1/empresa/credencial", status: 202, corpo: { "tentativa" => { "proximo_passo" => "aguardar" } })
    @ej.empresa.conectar("11111111000191", "senha-do-portal")
    assert_equal "PUT", @t.ultima.metodo
    assert_equal({ "cnpj" => "11111111000191", "senha" => "senha-do-portal", "ciente_ultima_tentativa" => false }, @t.ultima.json)
    @ej.empresa.conectar("11111111000191", "senha-do-portal", ciente_ultima_tentativa: true)
    assert_equal true, @t.ultima.json["ciente_ultima_tentativa"]

    @t.responder("PUT", "/v1/empresa/fiscal", corpo: { "ok" => true })
    @ej.empresa.fiscal(aliquota_simples: 6.0)
    assert_equal({ "aliquota_simples" => 6.0 }, @t.ultima.json)
    @ej.empresa.fiscal(reg_ap_trib_sn: 1)
    assert_equal({ "reg_ap_trib_sn" => 1 }, @t.ultima.json)

    @t.responder("GET", "/v1/empresa/onboarding", corpo: { "estado" => "perguntas" })
    assert_equal "perguntas", @ej.empresa.onboarding["estado"]
  end

  def test_tomadores_criar_obter_e_atualizar
    @t.responder("POST", "/v1/tomadores", status: 201, corpo: { "tomador" => { "tipo" => "pf", "id" => "t2" }, "ja_existia" => false })
    @ej.tomadores.criar("52998224725", nome: "Maria da Silva")
    assert_equal({ "documento" => "52998224725", "nome" => "Maria da Silva" }, @t.ultima.json)
    @ej.tomadores.criar("12345678000195")
    assert_equal({ "documento" => "12345678000195" }, @t.ultima.json)

    @t.responder("PUT", "/v1/tomadores/pf/t2", corpo: { "tomador" => { "id" => "t2" } })
    @ej.tomadores.atualizar("pf", "t2", email: "maria@exemplo.com.br", cep: "30130000")
    assert_equal({ "email" => "maria@exemplo.com.br", "cep" => "30130000" }, @t.ultima.json)
    @ej.tomadores.atualizar("pf", "t2", { "telefone" => "3133334444" })
    assert_equal({ "telefone" => "3133334444" }, @t.ultima.json)
  end

  def test_servicos
    @t.responder("POST", "/v1/servicos", status: 201, corpo: { "servico" => { "id" => "s1" } })
    @ej.servicos.criar(descricao: "Consultoria em TI", c_trib_nac: "010101", trib_issqn: "tributavel", retem_iss: false)
    assert_equal({ "descricao" => "Consultoria em TI", "c_trib_nac" => "010101", "trib_issqn" => "tributavel", "retem_iss" => false },
                 @t.ultima.json)

    @t.responder("PUT", "/v1/servicos/s1", corpo: { "servico" => { "id" => "s1" } })
    @ej.servicos.atualizar("s1", aliquota_iss: nil) # nil explícito vai como null: limpa o campo
    assert_equal({ "aliquota_iss" => nil }, @t.ultima.json)

    @t.responder("DELETE", "/v1/servicos/s1", corpo: { "servico" => { "id" => "s1", "ativo" => false } })
    @ej.servicos.desativar("s1")
    assert_equal "DELETE", @t.ultima.metodo
    assert_nil @t.ultima.corpo

    @t.responder("GET", "/v1/catalogo/servicos", corpo: { "itens" => [] })
    @ej.servicos.catalogo("consultoria em ti", limite: 5)
    assert_equal "q=consultoria+em+ti&limite=5", @t.ultima.query

    @t.responder("GET", "/v1/servicos", corpo: { "servicos" => [] })
    @ej.servicos.listar(ativos: true)
    assert_equal "ativos=1", @t.ultima.query
    @ej.servicos.listar(ativos: "todos")
    assert_equal "ativos=todos", @t.ultima.query
  end

  def test_notas_listar_e_cancelar
    @t.responder("GET", "/v1/notas", corpo: { "notas" => [], "total" => 0, "proximo_cursor" => nil })
    @ej.notas.listar(periodo: "personalizado", de: "2026-10-01", ate: "2026-10-31", situacao: "emitidas", limite: 50)
    assert_equal "periodo=personalizado&de=2026-10-01&ate=2026-10-31&situacao=emitidas&limite=50", @t.ultima.query

    @t.responder("POST", "/v1/notas/local/n1/cancelar", status: 202, corpo: { "operacao" => { "id" => "o1", "estado" => "processando" } })
    r = @ej.notas.cancelar("local", "n1", motivo: 1)
    assert_equal "o1", r["operacao"]["id"]
    assert_equal({ "motivo" => "1" }, @t.ultima.json)
    @ej.notas.cancelar("local", "n1", motivo: "2", justificativa: "Serviço cancelado pelo cliente")
    assert_equal({ "motivo" => "2", "justificativa" => "Serviço cancelado pelo cliente" }, @t.ultima.json)
  end

  def test_emissoes_obter_listar_e_conferir
    @t.responder("POST", "/v1/emissoes/p1/conferir", status: 202, corpo: pedido("autorizada"))
    assert_equal "autorizada", @ej.emissoes.conferir("p1")["pedido"]["estado"]
    assert_equal "POST", @t.ultima.metodo

    @t.responder("GET", "/v1/emissoes", corpo: { "pedidos" => [] })
    @ej.emissoes.listar(estados: "na_fila,emitindo")
    assert_equal "estados=na_fila%2Cemitindo", @t.ultima.query
  end
end
