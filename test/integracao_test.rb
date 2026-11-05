# frozen_string_literal: true

require_relative "test_helper"

# Integração opcional contra o sandbox (https://sandbox.emissaoja.com.br): Emissor Nacional simulado, nada vai ao
# fisco e nada é cobrado. Só roda com EMISSAOJA_TEST_KEY=ej_test_... definida; sem ela (como no CI), é pulada.
#
#   EMISSAOJA_TEST_KEY=ej_test_... bundle exec rake test
class IntegracaoSandboxTest < Minitest::Test
  def setup
    chave = ENV["EMISSAOJA_TEST_KEY"].to_s
    skip "defina EMISSAOJA_TEST_KEY (chave ej_test_ do sandbox) para rodar a integração" if chave.empty?
    skip "EMISSAOJA_TEST_KEY precisa ser uma chave do sandbox (ej_test_)" unless chave.start_with?("ej_test_")

    @ej = Emissaoja::Cliente.new(chave: chave, base_url: Emissaoja::BASE_SANDBOX)
  end

  def test_status_do_sandbox
    status = @ej.status
    assert_equal true, status["ok"]
    assert_equal "sandbox", status["ambiente"]
  end

  def test_emissao_completa_com_pdf_xml_e_idempotencia
    conectar_empresa_de_exemplo
    tomador = @ej.tomadores.criar("12345678000195")["tomador"]
    referencia = "ruby-#{Time.now.strftime("%Y%m%d%H%M%S")}-#{rand(1000..9999)}"
    valor = rand(100..9_000) # muda a cada execução: evita possivel_duplicada (nota igual no mesmo dia)
    campos = { tomador_tipo: tomador["tipo"], tomador_id: tomador["id"], valor: valor, descricao: "Teste de integração da gem emissaoja" }

    r = @ej.notas.emitir(referencia, **campos)
    pedido = @ej.notas.aguardar(r["pedido"]["id"])["pedido"]
    assert_equal "autorizada", pedido["estado"], pedido.inspect

    nota = pedido["nota"]
    assert @ej.notas.pdf(nota["origem"], nota["id"]).start_with?("%PDF"), "o PDF deveria começar com %PDF"
    assert_includes @ej.notas.xml(nota["origem"], nota["id"]), "<"

    repetido = @ej.notas.emitir(referencia, **campos)
    assert_equal true, repetido["repetido"]
    assert_equal pedido["id"], repetido["pedido"]["id"]
  end

  private

  # Conecta a empresa de exemplo 11111111000191 (MEI pronto para emitir) se a conta ainda não tem empresa e
  # espera o onboarding ficar pronto.
  def conectar_empresa_de_exemplo
    if @ej.empresa.obter["empresa"].nil?
      @ej.empresa.conectar("11111111000191", "qualquer-senha")
      @ej.empresa.aguardar_credencial
    end
    30.times do
      return if @ej.empresa.obter.dig("onboarding", "estado") == "pronto"

      sleep 2
    end
    flunk "o onboarding da empresa de exemplo não ficou pronto"
  end
end
