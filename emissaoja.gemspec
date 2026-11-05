# frozen_string_literal: true

require_relative "lib/emissaoja/version"

Gem::Specification.new do |spec|
  spec.name = "emissaoja"
  spec.version = Emissaoja::VERSION
  spec.authors = ["BINOBO LTDA"]
  spec.email = ["suporte@emissaoja.com.br"]

  spec.summary = "API de NFS-e nacional para Ruby: emita nota fiscal de serviço no Emissor Nacional, " \
                 "sem certificado digital, para MEI e Simples Nacional."
  spec.description = <<~DESCRICAO.split.join(" ")
    Cliente oficial (SDK) em Ruby da API do emissaoja (https://emissaoja.com.br): emita NFS-e nacional, a nota
    fiscal de serviço eletrônica, no Emissor Nacional (nfse.gov.br) com o CNPJ e a senha do portal, sem certificado
    digital, para MEI e empresas do Simples Nacional. Conecta a empresa, cadastra tomadores e serviços, emite com idempotência,
    acompanha o pedido e baixa o PDF (DANFSe) e o XML da nota. Sem dependências (Net::HTTP e JSON da biblioteca
    padrão), pronto para Rails e com ambiente de testes gratuito (sandbox).
    Official Ruby client for the emissaoja API: issue Brazilian NFS-e service invoices through the national
    Emissor Nacional, with no digital certificate.
  DESCRICAO
  spec.homepage = "https://emissaoja.com.br/docs/"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0"

  spec.metadata = {
    "homepage_uri" => "https://emissaoja.com.br/docs/",
    "documentation_uri" => "https://emissaoja.com.br/docs/",
    "source_code_uri" => "https://github.com/Easymovel/emissaoja-ruby",
    "changelog_uri" => "https://github.com/Easymovel/emissaoja-ruby/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/Easymovel/emissaoja-ruby/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.glob("lib/**/*.rb", base: __dir__).sort + %w[README.md LICENSE CHANGELOG.md]
  spec.require_paths = ["lib"]
end
