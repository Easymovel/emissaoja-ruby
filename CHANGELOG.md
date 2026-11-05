# Changelog

Todas as mudanças relevantes desta gem. Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/); versões seguem [SemVer](https://semver.org/lang/pt-BR/).

## [0.1.0] - 2026-11-05

Primeira versão pública.

### Adicionado

- `Emissaoja::Cliente` com os recursos `empresa` (obter, conectar, credencial, aguardar_credencial, onboarding, fiscal, reler_fisco), `tomadores` (listar, buscar, criar, obter, atualizar), `servicos` (listar, criar, atualizar, desativar, catalogo), `notas` (emitir, aguardar, listar, pdf, xml, cancelar), `emissoes` (obter, listar, conferir), `operacoes` (obter, aguardar), `cnpj.consultar` e `status`.
- `notas.emitir` com referência obrigatória, conferida antes da chamada (`chave_idempotencia_invalida`, sem ir à API) e enviada no cabeçalho `Idempotency-Key`; campos `nil` ficam fora do corpo.
- `notas.aguardar` no ritmo de `proxima_consulta_ms`; `empresa.aguardar_credencial` e `operacoes.aguardar` com intervalo e tempo máximo; `tempo_esgotado` com o `pedido_id` nos `extras`.
- `Emissaoja::Erro` com `status`, `code`, `message`, `extras`, `bloqueios` e `request_id` (cabeçalho `x-request-id`); falha de rede vira `rede` e tempo esgotado vira `tempo_esgotado`, com status 0.
- Chave lida de `EMISSAOJA_KEY` na primeira chamada que precisa dela, quando não informada; `inspect` do cliente não mostra a chave.
- `Emissaoja::BASE_PRODUCAO` e `Emissaoja::BASE_SANDBOX`.
- Transporte HTTP com `Net::HTTP` (sem dependências e sem repetição automática), substituível pela opção `transporte`; a espera dos métodos `aguardar` é substituível pela opção `dormir`.
- `BigDecimal` e `Rational` vão como número no JSON.

[0.1.0]: https://github.com/Easymovel/emissaoja-ruby/releases/tag/v0.1.0
