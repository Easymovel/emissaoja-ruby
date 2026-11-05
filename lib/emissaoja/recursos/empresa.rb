# frozen_string_literal: true

module Emissaoja
  module Recursos
    # A empresa da conta: conexão com o Emissor Nacional (CNPJ e senha do portal) e configuração fiscal.
    # Uma conta tem uma empresa.
    class Empresa < Base
      # GET /v1/empresa: empresa (nil antes de conectar), credencial, onboarding, importação e avisos.
      # @return [Hash]
      def obter
        json("GET", "/v1/empresa")
      end

      # PUT /v1/empresa/credencial: conecta a empresa com o CNPJ e a senha do Emissor Nacional. Responde na hora
      # (202) com a "tentativa"; a verificação no portal segue em segundo plano (acompanhe com #aguardar_credencial)
      # e, com a senha aceita, o emissaoja lê o cadastro fiscal e traz as notas dos últimos 90 dias.
      #
      # A verificação aceita até 3 senhas erradas por CNPJ em 24 h, para o portal não bloquear a conta da empresa:
      # confira a senha antes de tentar de novo.
      #
      # @param cnpj [String] só números
      # @param senha [String] senha do Emissor Nacional (não volta em nenhuma resposta)
      # @param ciente_ultima_tentativa [Boolean] true para confirmar a última tentativa permitida
      #   (quando a API responde 409 confirmar_ultima_tentativa)
      # @return [Hash] {"tentativa" => {"id" => ..., "estado" => ..., "proximo_passo" => "aguardar", ...}}
      def conectar(cnpj, senha, ciente_ultima_tentativa: false)
        corpo = { "cnpj" => cnpj.to_s, "senha" => senha.to_s, "ciente_ultima_tentativa" => ciente_ultima_tentativa ? true : false }
        json("PUT", "/v1/empresa/credencial", corpo: corpo)
      end

      # GET /v1/empresa/credencial: a tentativa em andamento (ou a última), com "estado" e "proximo_passo"
      # ("aguardar", "configurando", "pronto", "corrigir_senha", "tentar_mais_tarde", "redefinir_no_portal",
      # "suporte").
      # @return [Hash] {"credencial" => {...}, "onboarding" => {"estado" => ...}, "tentativa" => {...} ou nil}
      def credencial
        json("GET", "/v1/empresa/credencial")
      end

      # Consulta #credencial até a tentativa sair de "aguardar" (senha aceita ou recusada, portal fora...).
      # @param intervalo [Numeric] segundos entre as consultas (padrão 2)
      # @param timeout [Numeric] segundos no total (padrão 120)
      # @return [Hash] a última resposta de #credencial
      # @raise [Erro] code "tempo_esgotado" (status 0) se não terminar a tempo
      def aguardar_credencial(intervalo: 2, timeout: 120)
        fim = agora + timeout
        loop do
          resposta = credencial
          tentativa = resposta["tentativa"]
          return resposta unless tentativa.is_a?(Hash) && tentativa["proximo_passo"] == "aguardar"
          raise tempo_esgotado("A verificação da senha não terminou a tempo.") if agora >= fim

          esperar(intervalo)
        end
      end

      # GET /v1/empresa/onboarding: estágios, perguntas pendentes e bloqueio.
      # @return [Hash]
      def onboarding
        json("GET", "/v1/empresa/onboarding")
      end

      # PUT /v1/empresa/fiscal: responde as perguntas que o cadastro fiscal não responde sozinho (onboarding em
      # "perguntas"). Só os campos informados vão no corpo.
      # @param aliquota_simples [Numeric, nil] alíquota do Simples Nacional, em % (maior que 0, até 33)
      # @param reg_ap_trib_sn [Integer, nil] regime de apuração dos tributos do Simples Nacional: 1, 2 ou 3
      # @return [Hash]
      def fiscal(aliquota_simples: nil, reg_ap_trib_sn: nil)
        corpo = {}
        corpo["aliquota_simples"] = aliquota_simples unless aliquota_simples.nil?
        corpo["reg_ap_trib_sn"] = reg_ap_trib_sn unless reg_ap_trib_sn.nil?
        json("PUT", "/v1/empresa/fiscal", corpo: corpo)
      end

      # POST /v1/empresa/reler-fisco: lê o cadastro fiscal de novo no portal (202).
      # @return [Hash]
      def reler_fisco
        json("POST", "/v1/empresa/reler-fisco")
      end
    end
  end
end
