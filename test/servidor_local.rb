# frozen_string_literal: true

require "socket"

# Servidor HTTP/1.1 mínimo em 127.0.0.1, numa porta livre, para testar o transporte Net::HTTP de verdade sem
# sair da máquina. Atende uma requisição por conexão. O bloco recebe a Requisicao e devolve
# [status, cabecalhos, corpo], ou nil para segurar a conexão sem responder (simula a API que não responde).
class ServidorLocal
  Requisicao = Struct.new(:metodo, :alvo, :cabecalhos, :corpo)

  attr_reader :requisicoes

  def initialize(&responder)
    @responder = responder
    @requisicoes = []
    @presas = []
    @servidor = TCPServer.new("127.0.0.1", 0)
    @porta = @servidor.addr[1]
    @thread = Thread.new { atender }
  end

  def url
    "http://127.0.0.1:#{@porta}"
  end

  def fechar
    @servidor.close
    @thread.join(5) || @thread.kill
    @presas.each(&:close)
  end

  private

  def atender
    loop { atender_conexao(@servidor.accept) }
  rescue IOError, SystemCallError
    nil # o servidor foi fechado em #fechar
  end

  def atender_conexao(conexao)
    requisicao = ler(conexao)
    @requisicoes << requisicao
    resposta = @responder.call(requisicao)
    if resposta.nil?
      @presas << conexao
    else
      escrever(conexao, *resposta)
      conexao.close
    end
  rescue IOError, SystemCallError
    conexao.close
  end

  def ler(conexao)
    metodo, alvo = conexao.gets("\r\n").to_s.split(" ")
    cabecalhos = {}
    while (linha = conexao.gets("\r\n")) && linha != "\r\n"
      nome, valor = linha.split(":", 2)
      cabecalhos[nome.strip.downcase] = valor.to_s.strip
    end
    tamanho = cabecalhos["content-length"].to_i
    Requisicao.new(metodo, alvo, cabecalhos, tamanho.positive? ? conexao.read(tamanho) : nil)
  end

  def escrever(conexao, status, cabecalhos, corpo)
    corpo = corpo.to_s.b
    linhas = ["HTTP/1.1 #{status} OK"]
    cabecalhos.each { |nome, valor| linhas << "#{nome}: #{valor}" }
    linhas << "Content-Length: #{corpo.bytesize}" << "Connection: close"
    conexao.write("#{linhas.join("\r\n")}\r\n\r\n".b + corpo)
  end
end
