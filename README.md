# emissaoja: API de NFS-e nacional para Ruby

Gem oficial em Ruby da [API do emissaoja](https://emissaoja.com.br/docs/): emita **NFS-e (nota fiscal de serviço eletrônica) no Emissor Nacional** a partir do seu sistema Ruby ou Rails, com o CNPJ e a senha do portal, **sem certificado digital**, para MEI e empresas do Simples Nacional. Conecte a empresa, cadastre tomadores e serviços, emita a nota, acompanhe o pedido e baixe o PDF (DANFSe) e o XML.

- **Sem dependências**: só `Net::HTTP` e `JSON` da biblioteca padrão, Ruby 3.0 ou mais novo.
- **Idempotência embutida**: `emitir` exige uma referência sua por nota e a envia como `Idempotency-Key`; repetir a chamada devolve o mesmo pedido, sem emitir de novo.
- **Erros com código estável**: toda falha vira `Emissaoja::Erro`, com `code` (a lista fechada da API), `status`, `extras`, `bloqueios` e `request_id`.
- **Acompanhamento pronto**: `notas.aguardar` consulta o pedido no ritmo que a API pede (`proxima_consulta_ms`).
- **Feita para Rails**: uma instância serve a aplicação inteira (Puma, Sidekiq), a chave só é lida na primeira chamada e o transporte HTTP pode ser trocado nos testes.

> **A chave de API é secreta.** Quem tem a chave emite notas em nome da empresa. Guarde-a no servidor (credentials do Rails, variável de ambiente, cofre de segredos), nunca no código-fonte, no Git, no navegador ou em app distribuído.

## Instalação

```bash
bundle add emissaoja
```

Ou, fora do Bundler:

```bash
gem install emissaoja
```

Para usar a API, crie a conta grátis em [emissaoja.com.br](https://emissaoja.com.br/?origem=lib-ruby): entre no [app](https://emissaoja.com.br/app) com a conta Google, aceite os termos e crie a chave em **Conta → API** (ela aparece uma vez e começa com `ej_live_`). Depois, conecte a empresa com o CNPJ e a senha do Emissor Nacional (`ej.empresa.conectar`).

## Teste no sandbox em 2 minutos

O sandbox, em [sandbox.emissaoja.com.br](https://sandbox.emissaoja.com.br), é o mesmo emissaoja com um **Emissor Nacional simulado**: nada vai ao fisco e nada é cobrado. Entre com a conta Google, aceite os termos e crie uma chave em **Conta → API** (ela começa com `ej_test_` e só vale lá).

```ruby
require "emissaoja"

# EMISSAOJA_KEY=ej_test_... (chave do sandbox)
ej = Emissaoja::Cliente.new(chave: ENV["EMISSAOJA_KEY"], base_url: Emissaoja::BASE_SANDBOX)

# 1. Conectar a empresa de exemplo, uma vez (MEI pronto para emitir; no sandbox qualquer senha serve, menos "errada")
if ej.empresa.obter["empresa"].nil?
  ej.empresa.conectar("11111111000191", "qualquer-senha")
  ej.empresa.aguardar_credencial # até o portal aceitar a senha
end

# 2. Esperar o cadastro fiscal ser lido (onboarding "pronto"; no sandbox, poucos segundos)
30.times do
  break if ej.empresa.obter.dig("onboarding", "estado") == "pronto"

  sleep 2
end

# 3. Tomador pelo CNPJ: nome e endereço vêm da Receita (se já existe, volta o mesmo)
tomador = ej.tomadores.criar("12345678000195")["tomador"]

# 4. Emitir: a referência é um id seu, único por nota. Repetir com a mesma referência devolve o mesmo
#    pedido; para emitir outra nota (outro valor, outro tomador), use outra referência.
r = ej.notas.emitir(
  "pedido-0001",
  tomador_tipo: tomador["tipo"],
  tomador_id: tomador["id"],
  valor: 1500,
  descricao: "Consultoria de novembro"
)

# 5. Acompanhar até autorizada, recusada ou incerta e baixar o PDF
pedido = ej.notas.aguardar(r["pedido"]["id"])["pedido"]
if pedido["estado"] == "autorizada"
  puts "NFS-e #{pedido["numero"]}, chave de acesso #{pedido["chave_acesso"]}"
  File.binwrite("nota.pdf", ej.notas.pdf(pedido["nota"]["origem"], pedido["nota"]["id"]))
else
  puts "#{pedido["estado"]}: #{pedido["motivo"]}"
end
```

Empresas de exemplo do sandbox (qualquer senha, menos `errada`, que o portal simulado recusa):

| CNPJ | O que acontece |
| --- | --- |
| `11111111000191` | MEI pronto para emitir, com notas e clientes dos últimos 90 dias |
| `22222222000191` | ME/EPP que pede a alíquota do Simples antes de emitir (`ej.empresa.fiscal(aliquota_simples: ...)`) |
| `33333333000191` | MEI sem notas anteriores |
| `44444444000191` | Empresa bloqueada (não optante do Simples) |

Tomadores de exemplo: CNPJ `12345678000195` e CPF `52998224725`. Valores com significado ao emitir: `13.13` sai **incerta** (`ej.emissoes.conferir(id)` confere e ela vira autorizada), `77.77` sai incerta e a conferência mostra que a nota não saiu, `99.99` é **recusada** pelo fisco simulado. O sandbox é reiniciado a cada publicação do emissaoja: a empresa continua conectada, mas as notas emitidas antes somem.

## Em produção

Troque a base e a chave. Sem `base_url`, o cliente usa produção (`https://emissaoja.com.br`); sem `chave`, lê `EMISSAOJA_KEY` na primeira chamada.

```ruby
ej = Emissaoja::Cliente.new # produção; EMISSAOJA_KEY=ej_live_...

# Uma vez: CNPJ (só números) e senha do Emissor Nacional da empresa
ej.empresa.conectar("11222333000181", ENV.fetch("SENHA_EMISSOR_NACIONAL"))
tentativa = ej.empresa.aguardar_credencial["tentativa"]
puts tentativa["proximo_passo"] # "configurando" ou "pronto"; ou "corrigir_senha", "redefinir_no_portal"...
```

- As chaves `ej_live_` só valem em produção e as `ej_test_` só no sandbox. A chave é secreta: só no servidor, nunca no navegador ou em app distribuído.
- A verificação aceita até 3 senhas erradas por CNPJ em 24 h, para o portal não bloquear a conta da empresa: confira a senha antes de tentar de novo.
- A senha do portal nunca volta em resposta nem aparece em log.
- Opções do cliente: `chave:`, `base_url:` (`Emissaoja::BASE_PRODUCAO` ou `Emissaoja::BASE_SANDBOX`), `timeout:` (segundos, padrão 30), `transporte:` e `dormir:` (para testes).

## Recursos

Todas as respostas são `Hash` com chaves `String`: o JSON da API, em `snake_case`. A referência completa dos campos está na [documentação](https://emissaoja.com.br/docs/) e no [OpenAPI](https://emissaoja.com.br/v1/openapi.json).

### Empresa

```ruby
ej.empresa.obter                         # empresa (nil antes de conectar), credencial, onboarding e avisos
ej.empresa.conectar(cnpj, senha)         # 202 {"tentativa" => {...}}; a verificação segue em segundo plano
ej.empresa.aguardar_credencial           # repete credencial até proximo_passo sair de "aguardar"
ej.empresa.onboarding                    # estágios e perguntas pendentes (estado "perguntas")
ej.empresa.fiscal(aliquota_simples: 6.0) # responde a pergunta do Simples (há também reg_ap_trib_sn: 1, 2 ou 3)
ej.empresa.reler_fisco                   # lê o cadastro fiscal de novo no portal
```

`onboarding.estado` segue `configurando → perguntas → pronto`. Emitir antes de `pronto` devolve `422 nota_bloqueada` com o que falta.

### Tomadores

```ruby
pj = ej.tomadores.criar("12345678000195")["tomador"]                      # CNPJ: dados da Receita
pf = ej.tomadores.criar("52998224725", nome: "Maria da Silva")["tomador"] # CPF: com o nome
ej.tomadores.buscar("maria")["tomadores"]                                 # por nome ou documento
ej.tomadores.listar(busca: "silva", pagina: 1, limite: 20, ordem: "recentes")
ej.tomadores.obter("pf", pf["id"])
ej.tomadores.atualizar("pf", pf["id"], email: "maria@exemplo.com.br", cep: "30130000")
```

Tomador não se apaga: as notas emitidas apontam para ele.

### Serviços

```ruby
item = ej.servicos.catalogo("consultoria em informática", limite: 5)["itens"].first # catálogo nacional
servico = ej.servicos.criar(
  descricao: "Consultoria em TI",
  c_trib_nac: item["c_trib_nac"],
  trib_issqn: "tributavel", # ou "nao_incidencia"
  retem_iss: false
)["servico"]
ej.servicos.listar(ativos: "todos") # "1" (ativos), "0" (inativos) ou "todos"
ej.servicos.atualizar(servico["id"], descricao: "Consultoria em tecnologia")
ej.servicos.desativar(servico["id"]) # o último serviço ativo não pode ser desativado
```

`trib_issqn` aceita `tributavel` e `nao_incidencia`; isenção, imunidade e exportação ficam fora do emissaoja.

### Notas

```ruby
r = ej.notas.emitir(
  "venda-2026-000123",       # referência: um id seu, único por nota
  tomador_tipo: "pj",
  tomador_id: pj["id"],
  valor: 1500,               # reais, até 2 casas (Integer, Float ou BigDecimal)
  servico_id: servico["id"], # omitido: o serviço principal
  descricao: "Consultoria de novembro",
  competencia: "2026-11-01"  # omitida: hoje
)
pedido = ej.notas.aguardar(r["pedido"]["id"])["pedido"] # até autorizada, recusada ou incerta
nota = pedido["nota"]                                   # {"origem" => "local", "id" => ...}

File.binwrite("nota.pdf", ej.notas.pdf(nota["origem"], nota["id"])) # String binária (DANFSe)
File.write("nota.xml", ej.notas.xml(nota["origem"], nota["id"]))    # String UTF-8

# Lista paginada por cursor (periodo: "mes_atual", "mes_anterior", "ano_atual", "12_meses" ou "personalizado")
cursor = nil
loop do
  pagina = ej.notas.listar(periodo: "mes_atual", situacao: "emitidas", cursor: cursor)
  pagina["notas"].each { |n| puts "#{n["numero"]} #{n["valor"]}" }
  cursor = pagina["proximo_cursor"]
  break unless cursor
end

# Cancelar: motivo "1" (erro na emissão) ou "2" (serviço não prestado)
op = ej.notas.cancelar(nota["origem"], nota["id"], motivo: "1", justificativa: "Valor digitado errado na emissão")
ej.operacoes.aguardar(op["operacao"]["id"])["operacao"]["estado"] # "concluida" ou "falhou"
```

| `estado` do pedido | O que significa |
| --- | --- |
| `na_fila`, `emitindo`, `confirmando` | Em andamento; `aguardar` continua consultando |
| `autorizada` | A nota saiu: `numero`, `chave_acesso` e `nota` (`origem` e `id`, para o PDF e o XML) |
| `recusada` | O Emissor Nacional recusou: veja `motivo_code` e `motivo`. Recusada não conta no plano |
| `incerta` | O portal não confirmou se a nota saiu: confira com `ej.emissoes.conferir(pedido["id"])` antes de emitir de novo |

Nota não se altera: para corrigir, cancele e emita outra. Nota autorizada e depois cancelada conta no plano; recusada não.

### Emissões e operações

```ruby
ej.emissoes.listar(estados: %w[na_fila emitindo]) # pedidos em andamento
ej.emissoes.obter(pedido_id)                      # {"pedido" => {"estado" => ..., "proxima_consulta_ms" => ...}}
ej.emissoes.conferir(pedido_id)                   # pedido "incerta": confere no Emissor Nacional
ej.operacoes.obter(operacao_id)                   # cancelamento: processando, concluida ou falhou
```

### Consulta de CNPJ

```ruby
dados = ej.cnpj.consultar("11.222.333/0001-81") # com ou sem máscara
puts dados["razao_social"]
```

Devolve os dados cadastrais da Receita Federal (razão social, situação, CNAEs, endereço, Simples, MEI, sócios com CPF mascarado). Não cria tomador: `ej.tomadores.criar` já preenche pelo CNPJ.

### Status

```ruby
Emissaoja::Cliente.new.status # {"ok" => true, "versao" => "...", "motor" => "ok", "ambiente" => "producao", ...}
```

`status` não usa a chave.

## Erros

Toda resposta fora de `2xx` vira `Emissaoja::Erro`. Decida pelo `code`, nunca pelo texto da mensagem:

```ruby
begin
  ej.notas.emitir("pedido-0002", tomador_tipo: "pj", tomador_id: pj["id"], valor: 100)
rescue Emissaoja::Erro => e
  case e.code
  when "nota_bloqueada"
    e.bloqueios.each { |b| puts "#{b["code"]}: #{b["mensagem"]} (#{b["acao"]})" } # o que falta no cadastro
  when "limite_notas"
    puts "O limite do plano no mês acabou: https://emissaoja.com.br/#precos"
  else
    warn "#{e.status} #{e.code}: #{e.message} (request_id #{e.request_id})"
    raise
  end
end
```

`e.status` é o status HTTP (0 para erro local, de rede ou de tempo); `e.extras` traz os outros campos do corpo (`bloqueios`, `nota_igual_recente`, `pedido_id`, `retry_after`, `details`...); `e.request_id` é o cabeçalho `x-request-id`, útil para falar com o suporte.

| `code` | HTTP | O que fazer |
| --- | --- | --- |
| `chave_invalida` | 401, ou 0 sem chave | Confira a chave ou a variável `EMISSAOJA_KEY`: `ej_live_` em produção, `ej_test_` no sandbox |
| `validation_error`, `valor_invalido`, `tomador_obrigatorio`, `cnpj_invalido` | 400 | Corrija o campo indicado na mensagem (e em `e.extras["details"]`, quando vier) |
| `chave_idempotencia_invalida` | 0 (conferida aqui) ou 400 | Use uma referência de 8 a 64 caracteres: letras, números, `_` e `-` |
| `limite_notas` | 402 | O limite do plano no mês acabou; veja os [planos](https://emissaoja.com.br/#precos) |
| `tomador_nao_encontrado`, `servico_nao_encontrado`, `nota_nao_encontrada`, `pedido_nao_encontrado` | 404 | Confira o id (e o tipo `pj`/`pf` ou a origem `local`/`importada`) |
| `sem_empresa` | 409 | Conecte a empresa com `ej.empresa.conectar` |
| `aceite_pendente` | 409 | Aceite os termos no [app](https://emissaoja.com.br/app) |
| `possivel_duplicada`, `emissao_repetida_recente` | 409 | Nota igual recente: veja a seção abaixo |
| `chave_idempotencia_conflito` | 409 | A referência já foi usada numa nota com outros dados (`e.extras["pedido_id"]` é o pedido original): para outra nota, use outra referência |
| `incerta_pendente` | 409 | Há uma nota igual incerta (`e.extras["pedido_id"]`): confira com `ej.emissoes.conferir` antes de emitir de novo |
| `ultimo_servico_ativo` | 409 | O último serviço ativo não pode ser desativado |
| `nota_bloqueada` | 422 | A nota não pode sair assim: cada item de `e.bloqueios` traz `code`, `mensagem` e `acao` |
| `rate_limited` | 429 | Limite por minuto: espere `e.extras["retry_after"]` segundos e repita |
| `fila_indisponivel` | 503 | Repita `emitir` com a **mesma** referência |
| `motor_indisponivel`, `receita_indisponivel` | 503 | Portal ou serviço fora do ar: tente de novo mais tarde |
| `rede`, `tempo_esgotado` | 0 | Sem resposta da API: repita (em `emitir`, com a mesma referência). Em `aguardar`, o pedido continua: consulte depois com `ej.emissoes.obter(e.extras["pedido_id"])` |

**A biblioteca não repete chamadas sozinha.** Emitir tem efeito fiscal: quem decide repetir é o seu código, sempre com a mesma referência, e a API garante que a mesma referência nunca emite duas vezes.

## Idempotência e nota em dobro

- **Referência.** Cada nota que você quer emitir tem uma referência sua (o id do pedido de venda, por exemplo), de 8 a 64 caracteres: letras, números, `_` e `-`. A gem confere o formato antes de chamar a API e a envia no cabeçalho `Idempotency-Key`. Repetir `emitir` com a mesma referência devolve o mesmo pedido, com `"repetido" => true`, e nunca emite duas vezes. Por isso, depois de falha de rede, `tempo_esgotado` ou `503 fila_indisponivel`, repita com a **mesma** referência.
- **`possivel_duplicada`.** Já saiu hoje uma nota igual (mesmo tomador, valor e competência), descrita em `e.extras["nota_igual_recente"]`. Se for mesmo outra nota, repita com `permitir_repetida_de:` igual ao `pedido_id` informado.
- **`emissao_repetida_recente`.** A mesma nota foi pedida há menos de 2 minutos. Se for mesmo outra, repita com `confirmo_repeticao: true`.

```ruby
referencia = format("venda-%08d", venda.id) # a mesma venda gera sempre a mesma referência
campos = { tomador_tipo: "pj", tomador_id: tomador_id, valor: venda.total, descricao: venda.descricao }

tentativas = 0
begin
  r = ej.notas.emitir(referencia, **campos)
rescue Emissaoja::Erro => e
  tentativas += 1
  raise unless %w[rede tempo_esgotado fila_indisponivel].include?(e.code) && tentativas < 3

  sleep(2 * tentativas)
  retry # mesma referência: se o pedido já tinha sido criado, volta o mesmo
end
```

Quando a API avisa de nota igual e a pessoa confirma que é mesmo outra nota:

```ruby
begin
  r = ej.notas.emitir(referencia, **campos)
rescue Emissaoja::Erro => e
  raise unless e.code == "possivel_duplicada" && confirmado_pela_pessoa?(e.extras["nota_igual_recente"])

  r = ej.notas.emitir(referencia, **campos, permitir_repetida_de: e.extras["nota_igual_recente"]["pedido_id"])
end
```

## Rails

```ruby
# config/initializers/emissaoja.rb
EMISSAOJA = Emissaoja::Cliente.new(
  chave: Rails.application.credentials.dig(:emissaoja, :chave), # nil: lê EMISSAOJA_KEY na primeira chamada
  base_url: Rails.env.production? ? Emissaoja::BASE_PRODUCAO : Emissaoja::BASE_SANDBOX
)
```

A chave fica nas credentials (`bin/rails credentials:edit`):

```yaml
emissaoja:
  chave: ej_live_...
```

Em desenvolvimento e teste, use uma chave `ej_test_` do sandbox (credentials por ambiente ou `EMISSAOJA_KEY`). Como a chave só é lida na primeira chamada, subir a aplicação sem ela (por exemplo, no `assets:precompile`) não falha. O cliente não guarda conexão nem estado mutável: a mesma instância serve todas as threads do Puma e do Sidekiq.

Emitir num job, repetindo só o que é passageiro:

```ruby
# app/jobs/emitir_nota_job.rb
class EmitirNotaJob < ApplicationJob
  PASSAGEIROS = %w[rede tempo_esgotado rate_limited fila_indisponivel motor_indisponivel].freeze

  # Só os erros passageiros chegam aqui (veja o rescue): o job repete com a MESMA referência
  retry_on Emissaoja::Erro, wait: 30.seconds, attempts: 5

  def perform(venda_id)
    venda = Venda.find(venda_id)
    r = EMISSAOJA.notas.emitir(
      format("venda-%08d", venda.id),
      tomador_tipo: venda.tomador_tipo,
      tomador_id: venda.tomador_id,
      valor: venda.total, # BigDecimal vai como número
      descricao: venda.descricao
    )
    pedido = EMISSAOJA.notas.aguardar(r["pedido"]["id"])["pedido"]
    venda.update!(nfse_estado: pedido["estado"], nfse_numero: pedido["numero"])
  rescue Emissaoja::Erro => e
    raise if PASSAGEIROS.include?(e.code)

    venda.update!(nfse_estado: "erro", nfse_erro: e.code) # nota_bloqueada, limite_notas...: precisa de alguém
  end
end
```

`aguardar` ocupa o worker até o pedido terminar (no máximo `timeout:`, padrão 180 s). Com muitas notas, você pode emitir num job e consultar `EMISSAOJA.emissoes.obter(id)` em outro, agendado com `proxima_consulta_ms`.

## Testes no seu projeto

Troque o transporte HTTP por um lambda e nada sai da máquina:

```ruby
falso = lambda do |metodo, url, cabecalhos, corpo, timeout|
  [202, { "content-type" => "application/json" }, '{"pedido":{"id":"p1","estado":"na_fila"}}']
end
ej = Emissaoja::Cliente.new(chave: "ej_test_falsa", transporte: falso, dormir: ->(_segundos) {})
ej.notas.emitir("pedido-0001", tomador_tipo: "pj", tomador_id: "t1", valor: 10)["pedido"]["estado"] # "na_fila"
```

O transporte recebe `(metodo, url, cabecalhos, corpo, timeout)` e devolve `[status, cabecalhos, corpo]`; `dormir` recebe os segundos de espera dos métodos `aguardar`. Para testar contra a API de verdade, use o sandbox.

## Limites

- 60 chamadas por minuto por chave; emissões, 10 por minuto; buscas e catálogo, 120 por minuto; consulta de CNPJ, 30 por minuto. Acima disso, `429 rate_limited`.
- Plano Grátis: 1 nota por mês. A nota conta quando o Emissor Nacional aceita o pedido; recusada não conta. Planos em [emissaoja.com.br/#precos](https://emissaoja.com.br/#precos).
- Uma conta tem uma empresa. Para várias empresas, uma conta e uma chave por empresa.

## Perguntas frequentes

**Precisa de certificado digital?** Não. O emissaoja entra no Emissor Nacional com o CNPJ e a senha do próprio portal.

**Funciona para MEI?** Sim. Atende MEI, ME e EPP optantes pelo Simples Nacional. O CNPJ da empresa vai só com números (o CNPJ alfanumérico ainda não é aceito para a empresa).

**Tem ambiente de testes?** Sim: o sandbox (`Emissaoja::BASE_SANDBOX`), com o Emissor Nacional simulado, empresas e tomadores de exemplo e chaves `ej_test_`. Nada vai ao fisco e nada é cobrado.

**Quanto custa?** A gem é gratuita (licença MIT). A API tem o plano Grátis, com 1 nota por mês, e planos pagos em [emissaoja.com.br/#precos](https://emissaoja.com.br/#precos). O sandbox não tem custo.

**Tem webhook?** Ainda não. Acompanhe o pedido com `ej.notas.aguardar`, que consulta `GET /v1/emissoes/{id}` no ritmo de `proxima_consulta_ms`.

## Links

- Documentação: [emissaoja.com.br/docs](https://emissaoja.com.br/docs/) (também em Markdown: [docs.md](https://emissaoja.com.br/docs.md))
- OpenAPI 3.1: [emissaoja.com.br/v1/openapi.json](https://emissaoja.com.br/v1/openapi.json)
- Para IAs: [emissaoja.com.br/llms.txt](https://emissaoja.com.br/llms.txt)
- MCP (emitir pelo seu assistente de IA): `https://emissaoja.com.br/mcp`
- Status da API: [emissaoja.com.br/v1/status](https://emissaoja.com.br/v1/status)
- Suporte: [suporte@emissaoja.com.br](mailto:suporte@emissaoja.com.br)
- Código-fonte, issues e changelog: [github.com/Easymovel/emissaoja-ruby](https://github.com/Easymovel/emissaoja-ruby)

Bibliotecas oficiais em outras linguagens:

- JavaScript e TypeScript: npm [`emissaoja`](https://www.npmjs.com/package/emissaoja)
- Python: PyPI [`emissaoja`](https://pypi.org/project/emissaoja/)
- PHP: Packagist [`emissaoja/emissaoja`](https://packagist.org/packages/emissaoja/emissaoja)
- .NET: NuGet [`Emissaoja`](https://www.nuget.org/packages/Emissaoja)
- Go: [`emissaoja.com.br/go`](https://pkg.go.dev/emissaoja.com.br/go)
- Ruby: RubyGems [`emissaoja`](https://rubygems.org/gems/emissaoja) (esta gem)
- n8n: [`n8n-nodes-emissaoja`](https://www.npmjs.com/package/n8n-nodes-emissaoja)

## Licença

[MIT](LICENSE). Copyright (c) 2026 BINOBO LTDA (CNPJ 68.649.497/0001-07), Belo Horizonte (MG).

## In English

**emissaoja** is a Brazilian NFS-e (service invoice) API, and this is its official Ruby gem. It issues invoices through the national Emissor Nacional using the company's CNPJ and portal password, with no digital certificate, for MEI and Simples Nacional companies. It has no runtime dependencies (Net::HTTP and JSON from the standard library), runs on Ruby 3.0+ and Rails, sends an idempotency key with every invoice and downloads the PDF and XML. Try it for free in the sandbox at [sandbox.emissaoja.com.br](https://sandbox.emissaoja.com.br); the documentation (in Portuguese) is at [emissaoja.com.br/docs](https://emissaoja.com.br/docs/).

---

O emissaoja é um serviço privado e não tem vínculo com a Receita Federal nem com o Emissor Nacional.
